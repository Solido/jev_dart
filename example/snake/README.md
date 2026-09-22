# Jev Snake

An interactive Snake demo where Jev chooses each move. The app is a standalone
Dart package using the local `jev_dart` package and Nocterm.

## Requirements

- Dart 3.5 or newer
- A TypeSafe API key in `TYPESAFE_API_KEY` or `JEV_API_KEY`
- A terminal at least 104 columns by 35 rows

## Run

From the repository root:

```sh
cd example/snake
dart pub get
dart run bin/snake.dart
```

The demo sends one System One request per move using the `jev-latest` model.
Moves are paced at 12 per second when responses arrive quickly; slower API
responses naturally slow the game. Jev's probabilities are shown beside the
board. A cycle safety shield prevents an unsafe proposed move from being
executed.

Controls:

- `Space`: pause or resume
- `↑` / `↓`: change the target speed
- `R`: start a new round
- `Enter`: retry after an API error
- `Q`, `Ctrl+C` or `Option+C`: quit

Run the checks from this directory with `dart analyze` and `dart test`.
