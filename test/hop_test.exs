defmodule HopTest do
  use ExUnit.Case
  doctest Hop

  @bandit_spec {Bandit, plug: HopTest.Server, scheme: :http, port: 4000}

  test "crawl with validations" do
    _pid = start_link_supervised!(@bandit_spec)
    Req.Test.stub(ServerStub, HopTest.Server)

    Hop.new("http://localhost/", config: [req_options: [plug: {Req.Test, ServerStub}]])
    |> Hop.stream()
    |> Enum.each(fn {url, _response, %{robots: robots}} ->
      assert is_map(robots)
      send(self(), {:url, url})
    end)

    assert_received {:url, "http://localhost/"}, "Did not visit /"

    assert_received {:url, "http://localhost/valid"}, "Did not visit /valid"

    refute_received {:url, "http://localhost/private"},
                    "Visited /private despite disallow rule in robots.txt"

    refute_received {:url, "http://localhost/invalid-mime"},
                    "Visited /invalid-mime"

    refute_received {:url, "http://localhost/large-content"},
                    "Visited /large-content"
  end
end
