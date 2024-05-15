FROM elixir:1.16.2

WORKDIR /app

COPY . .

ENV MIX_ENV=prod

CMD ["elixir", "static_chess.exs"]