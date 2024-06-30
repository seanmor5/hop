defmodule HopTest.Server do
  import Temple
  use Plug.Router, init_mode: :runtime

  if Mix.env() in [:dev, :test] do
    use Plug.Debugger
  end

  plug :match
  plug :dispatch
  # plug Plug.Logger, log: :debug

  match "/", via: [:get, :head] do
    {:safe, bod} =
      temple do
        "<!DOCTYPE html>"

        html do
          body do
            for url <- [
                  "/valid",
                  "/large-content",
                  "/invalid-mime",
                  "/non-http",
                  "/bad-host",
                  "/private"
                ] do
              a href: url
            end
          end
        end
      end

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, bod)
  end

  match "/invalid-mime", via: [:get, :head] do
    conn
    |> put_resp_content_type("application/javascript")
    |> send_resp(200, "function(){}")
  end

  match "/large-content", via: [:get, :head] do
    conn
    |> put_resp_header("content-length", 10_000_000_000 |> to_string())
    |> send_resp(200, "spoofed")
  end

  match "/private", via: [:get, :head] do
    send_resp(conn, 403, "This page is not allowed for crawling")
  end

  match "/valid", via: [:get, :head] do
    send_resp(conn, 200, "Success!")
  end

  get "/robots.txt" do
    robots_content = """
    User-agent: *
    Disallow: /private
    """

    send_resp(conn, 200, robots_content)
  end

  match _ do
    send_resp(conn, 404, "Page not found")
  end
end
