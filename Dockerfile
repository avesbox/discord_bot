FROM dart:latest AS build

WORKDIR /app

COPY . ./
COPY pubspec.* ./
RUN dart pub get
COPY . .

RUN dart pub get --offline
RUN mkdir -p dist
RUN dart compile exe bin/sunny.dart -o dist/app

FROM scratch
EXPOSE 8080
COPY --from=build /runtime/ /
COPY --from=build /app/dist/app /app/bin/

CMD ["/app/bin/app"]
  