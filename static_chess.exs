Mix.install([:plug, :bandit, :chess_logic])

defmodule StaticChess do
  import Plug.Conn
  alias ChessLogic.{Game, Move, Position}

  @base_url if Mix.env() == :prod,
              do: "https://chess.elliotekj.com",
              else: "http://localhost:4000"

  @repo_url "https://github.com/elliotekj/static_chess"

  @pieces %{
    "P" => "♟︎",
    "R" => "♜",
    "B" => "♝",
    "N" => "♞",
    "K" => "♚",
    "Q" => "♛"
  }

  def init(options), do: options

  def call(conn, _opts) do
    %{query_params: query_params} = fetch_query_params(conn)
    game = get_game(query_params)
    selected = get_selected(query_params)
    html = html(game: game, selected: selected)

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, html)
  end

  # https://github.com/phoenixframework/phoenix_live_view/blob/a793a04af6a91322404c514a2b6fa1a4a81b82ca/lib/phoenix_component.ex#L791C2-L807C6
  defmacrop sigil_H({:<<>>, meta, [expr]}, []) do
    options = [
      file: __CALLER__.file,
      line: __CALLER__.line + 1,
      caller: __CALLER__,
      indentation: meta[:indentation] || 0,
      source: expr
    ]

    EEx.compile_string(expr, options)
  end

  defp get_game(params) do
    case Map.get(params, "game") do
      pgn when pgn in [nil, ""] -> Game.new()
      pgn -> Base.decode64!(pgn) |> Game.from_pgn() |> List.first()
    end
  end

  defp get_selected(params) do
    case Map.get(params, "selected") do
      selected when selected in [nil, ""] -> nil
      selected -> String.to_integer(selected)
    end
  end

  defp get_square(assigns) do
    square_key = 16 * assigns[:row] + assigns[:col]
    pieces = assigns[:game].current_position.pieces
    piece = Enum.find(pieces, &(&1.square == square_key))
    selected? = assigns[:selected] == square_key

    selected_piece = get_selected_piece(pieces, assigns[:selected])
    possible_moves = get_possible_moves(assigns[:game], selected_piece)
    possible_move = get_possible_move(possible_moves, square_key)

    class =
      ["square"]
      |> get_color_class(piece)
      |> get_selected_class(selected?)
      |> get_possible_move_class(possible_move)
      |> Enum.join(" ")

    params = build_params(assigns[:game], possible_move, square_key)

    href =
      URI.new!(@base_url)
      |> URI.parse()
      |> Map.put(:query, URI.encode_query(params))
      |> URI.to_string()

    ~H"""
    <div class="<%= class %>">
      <%= if piece == nil && possible_move == nil do %>
        <span></span>
      <% else %>
        <a href="<%= href %>">
          <%= if piece != nil do %>
            <%= Map.get(get_attr(:pieces), ChessLogic.Piece.symbol(piece)) %>
          <% end %>
        </a>
      <% end %>
    </div>
    """
  end

  defp get_selected_piece(_pieces, nil), do: nil
  defp get_selected_piece(pieces, selected), do: Enum.find(pieces, &(&1.square == selected))

  defp get_possible_moves(_game, nil), do: []

  defp get_possible_moves(game, piece) do
    Position.all_possible_moves_from(game.current_position, piece)
  end

  defp get_possible_move(_possible_moves, nil), do: nil
  defp get_possible_move([], _square_key), do: nil

  defp get_possible_move(possible_moves, square_key) do
    Enum.find(possible_moves, &(&1.to.square == square_key))
  end

  defp get_color_class(class, %ChessLogic.Piece{color: :white}), do: ["w" | class]
  defp get_color_class(class, %ChessLogic.Piece{color: :black}), do: ["b" | class]
  defp get_color_class(class, nil), do: class

  defp get_selected_class(class, true), do: ["selected highlight" | class]
  defp get_selected_class(class, false), do: class

  defp get_possible_move_class(class, nil), do: class
  defp get_possible_move_class(class, _possible_move), do: ["highlight" | class]

  defp build_params(game, nil, selected) do
    %{game: encode_game(game), selected: selected}
  end

  defp build_params(game, move, _selected) do
    move = Move.move_to_string(move)
    {:ok, game} = Game.play(game, move)
    %{game: encode_game(game), selected: nil}
  end

  defp encode_game(%Game{history: []}), do: nil

  defp encode_game(game) do
    """
    [Event "StaticChess"]
    [Site "#{@base_url}"]
    [Date "????.??.??"]
    [Round "?"]
    [White "?"]
    [Black "?"]
    [Result "?"]
    #{Game.to_pgn(game)}
    """
    |> Base.encode64()
  end

  defp get_info([game: %Game{status: :started}] = assigns) do
    turn = assigns[:game].current_position.turn

    ~H"""
    It is <%= if turn == :white, do: "white's", else: "black's" %> turn. Click a piece to make a move.
    """
  end

  defp get_info(game: %Game{status: :over, winner: nil}) do
    ~H"""
    Game is over. It's a draw.
    """
  end

  defp get_info(game: %Game{status: :over, winner: winner}) do
    ~H"""
    Game is over. <%= if winner == :white, do: "White's", else: "Black's" %> win.
    """
  end

  defp get_attr(:repo_url), do: @repo_url
  defp get_attr(:pieces), do: @pieces

  defp html(assigns) do
    ~H"""
    <html>
      <head>
        <title>Static Chess</title>
        <meta name="viewport" content="width=device-width, initial-scale=1.0" />
        <link rel="icon" href="https://fav.farm/♟️" />
        <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/github-fork-ribbon-css/0.2.3/gh-fork-ribbon.min.css" />
        <style><%= css() %></style>
      </head>
      <body>
        <a href="<%= get_attr(:repo_url) %>" rel="source" target="_blank" class="github-fork-ribbon" data-ribbon="Fork on GitHub">
          Fork on GitHub
        </a>
        <h1>Static Chess</h1>
        <div>
          <a href="<%= get_attr(:repo_url) %>">info</a> - <a href="/">reset</a>
        </div>
        <div class="board">
          <%= for row <- 7..0 do %>
            <div class="row">
              <%= for col <- 0..7 do %>
                <%= get_square(game: @game, row: row, col: col, selected: @selected) %>
              <% end %>
            </div>
          <% end %>
        </div>
        <div class="info">
          <%= get_info(game: @game) %>
        </div>
      </body>
    </html>
    """
  end

  defp css do
    """
    body {
      text-align: center;
      font-family: sans-serif;
      margin-top: 30px;
    }
    div {
      box-sizing: border-box;
    }
    .board {
      display: flex;
      flex-direction: column;
      max-width: 500px;
      margin: 30px auto;
      border: 1px solid #333;
    }
    .info {
      max-width: 500px;
      margin: 10px auto;
    }
    .row {
      width: 100%;
      display: flex;
      flex-direction: row;
    }
    .square {
      width: calc(100% / 8);
      aspect-ratio: 1 / 1;
      font-size: 3.3em;
      position: relative;
    }
    .square a, .square span {
      border: 2px solid #00000000;
      text-decoration: none;
      color: inherit;
      display: block;
      box-sizing: border-box;
      width: 100%;
      height: 100%;
      position: absolute;
    }
    @media (hover) {
      .square a:hover {
        border: 2px solid #ddd;
      }
    }
    .square.selected a {
      border: 2px solid #ddd;
    }
    .square.w {
      color: white;
    }
    .board .row:nth-child(odd) .highlight.square:nth-child(even),
    .board .row:nth-child(even) .highlight.square:nth-child(odd){
      background-color: #506d53;
    }
    .board .row:nth-child(odd) .highlight.square:nth-child(odd),
    .board .row:nth-child(even) .highlight.square:nth-child(even){
      background-color: #607d63;
    }
    .board .row:nth-child(odd) .square:nth-child(even),
    .board .row:nth-child(even) .square:nth-child(odd){
      background-color: #868686;
    }
    .board .row:nth-child(odd) .square:nth-child(odd),
    .board .row:nth-child(even) .square:nth-child(even){
      background-color: #acacac;
    }
    """
  end
end

webserver = {Bandit, plug: StaticChess, scheme: :http, port: 4000}
{:ok, _} = Supervisor.start_link([webserver], strategy: :one_for_one)
Process.sleep(:infinity)
