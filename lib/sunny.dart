import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:nyxx/nyxx.dart';
import 'package:serinus/serinus.dart';

// Configuration
final discordToken = Platform.environment['DISCORD_TOKEN'] ?? ''; // Replace with your bot token or set as env variable
final channelId = Platform.environment['CHANNEL_ID'] ?? ''; // Replace with your channel ID or set as env variable
final webhookSecret = Platform.environment['WEBHOOK_SECRET'] ?? '';
const port = 8080;
final issueColor = fromHexString('#E36209'); // GitHub's standard orange for issues
final prColor = fromHexString('#6F42C1'); // GitHub's standard purple for PRs
final completedPrColor = fromHexString('#28A745'); // GitHub's green for merged PRs
final closedIssueColor = fromHexString('#6A737D'); // GitHub's gray for closed issues

late NyxxGateway bot;

Future<void> main() async {
  if (discordToken.isEmpty) {
    print('Warning: DISCORD_TOKEN environment variable is not set. Bot will not be able to connect to Discord.');
    throw StateError('Missing DISCORD_TOKEN environment variable');
  }
  if (channelId.isEmpty) {
    print('Warning: CHANNEL_ID environment variable is not set. Bot will not be able to send messages.');
    throw StateError('Missing CHANNEL_ID environment variable');
  }
  if (webhookSecret.isEmpty) {
    print('Warning: WEBHOOK_SECRET environment variable is not set. Webhook signature verification will fail.');
    throw StateError('Missing WEBHOOK_SECRET environment variable');
  }
  // 1. Initialize Discord Bot
  bot = await Nyxx.connectGateway(
    discordToken, 
    GatewayIntents.allUnprivileged,
    options: GatewayClientOptions(
      plugins: [
        cliIntegration,
        logging,
      ]
    )
  );
  final botUser = await bot.user.fetch();
  print('Discord Bot connected as ${botUser.username}!');

  // 2. Define Webhook Routes
  final app = await serinus.createMinimalApplication(
    port: port
  );

  app.post('/webhook', (RequestContext<Map<String, dynamic>> context) async {

    final signatureHeader = context.headers['x-hub-signature-256'];
    
    if (signatureHeader == null) {
      print('Missing signature header.');
      throw ForbiddenException('Missing signature');
    }

    // 3. Calculate the HMAC SHA256 hash
    final secretBytes = utf8.encode(webhookSecret);
    final payloadBytes = utf8.encode(jsonEncode(context.body));
    
    final hmac = Hmac(sha256, secretBytes);
    final digest = hmac.convert(payloadBytes);
    
    // GitHub formats the header as "sha256=<hash>"
    final expectedSignature = 'sha256=$digest';

    // 4. Compare the signatures
    // (Note: In highly secure environments, use a constant-time comparison 
    // to prevent timing attacks, but a simple comparison is fine for basic bots).
    if (signatureHeader != expectedSignature) {
      print('Signature mismatch! Expected: $expectedSignature, Got: $signatureHeader');
      throw ForbiddenException('Invalid signature');
    }

    // 2. Read the RAW payload (must be done before any JSON decoding)
    final data = context.body;
    final event = context.headers['x-github-event'];

    MessageBuilder? messageBuilder;

    if (event == 'issues') {
      final action = data['action'];
      final issue = data['issue'];
      final repoName = data['repository']['full_name'];
      final sender = data['sender'];

      // GitHub issue bodies can be long; Discord caps embed descriptions at 4096 chars.
      String body = issue['body'] ?? '*No description provided.*';
      if (body.length > 1000) {
        body = '${body.substring(0, 1000)}\n\n...[truncated]';
      }
      final color = switch(issue['state']) {
        'open' => issueColor,
        'closed' => closedIssueColor,
        _ => issueColor,
      };
      // Build the Embed
      final embed = EmbedBuilder(
        // GitHub's standard orange for issues
        color: color,
        
        // e.g., "[serverpod/serverpod] Issue opened: #4776 check constraint support"
        title: '[$repoName] Issue $action: #${issue['number']} ${issue['title']}',
        
        // Makes the title clickable
        url: Uri.parse(issue['html_url']), 
        
        // The actual markdown content from the GitHub issue
        description: body, 
        
        // The user who triggered the action
        author: EmbedAuthorBuilder(
          name: sender['login'],
          iconUrl: Uri.parse(sender['avatar_url']),
        ),
      );

      messageBuilder = MessageBuilder(embeds: [embed]);
    } 
    // You can do the exact same EmbedBuilder logic for 'pull_request' here!
    if (event == 'pull_request') {
      final action = data['action'];
      final pr = data['pull_request'];
      final repoName = data['repository']['full_name'];
      final sender = data['sender'];

      String body = pr['body'] ?? '*No description provided.*';
      if (body.length > 500) {
        body = '${body.substring(0, 500)}\n\n...[truncated]';
      }
      final color = switch(pr['state']) {
        'open' => prColor,
        'closed' when pr['merged_at'] != null => completedPrColor,
        'closed' => closedIssueColor,
        _ => prColor,
      };
      final embed = EmbedBuilder(
        author: EmbedAuthorBuilder(
          name: sender['login'],
          iconUrl: Uri.parse(sender['avatar_url']),
        ),
        color: color,
        title: '[$repoName] Pull Request $action: #${pr['number']} ${pr['title']}',
        url: Uri.parse(pr['html_url']),
        description: switch(pr['state']) {
          'closed' => null,
          _ => body,
        },
      );
      messageBuilder = MessageBuilder(embeds: [embed]);
    }
    if (messageBuilder != null) {
      try {
        final channel = await bot.channels.fetch(Snowflake.parse(channelId));
        if (channel case PartialTextChannel textChannel) {
          await textChannel.sendMessage(messageBuilder);
        }
      } catch (e) {
        print('Failed to send embed: $e');
      }
    }

    return 'OK';
  });

  // 3. Start Server
  await app.serve();
}

//1ZiZhNuAf6hR6CQQUogeZFXmEkj_5B8fcKJTRcY2JnY8apAbk

//

DiscordColor fromHexString(String hex) {
  final cleanHex = hex.replaceAll('#', '');
  final intColor = int.parse(cleanHex, radix: 16);
  return DiscordColor(intColor);
}