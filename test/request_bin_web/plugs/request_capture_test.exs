defmodule RequestBinWeb.Plugs.RequestCaptureTest do
  use ExUnit.Case, async: false

  alias RequestBin.Requests
  alias RequestBinWeb.Plugs.RequestCapture

  @parser_opts RequestCapture.init(
                 parsers: [:urlencoded, :multipart, :json],
                 pass: ["*/*"],
                 json_decoder: Jason
               )

  setup do
    original = Application.fetch_env!(:request_bin, :request_capture)
    on_exit(fn -> Application.put_env(:request_bin, :request_capture, original) end)
    :ok
  end

  test "captures exact collector bodies and original methods" do
    body = ~s({ "event": true })

    conn =
      "POST"
      |> Plug.Test.conn("/bin/example?source=test", body)
      |> Plug.Conn.put_req_header("content-type", "application/json")
      |> RequestCapture.call(@parser_opts)

    assert conn.private.request_bin_collector
    assert conn.private.request_bin_original_method == "POST"
    assert conn.private.request_bin_raw_body == body
    assert conn.body_params == %{}
    assert conn.query_params == %{"source" => "test"}
  end

  test "collector method override input remains the original POST" do
    body = "_method=DELETE&event=created"

    conn =
      "POST"
      |> Plug.Test.conn("/bin/example", body)
      |> Plug.Conn.put_req_header("content-type", "application/x-www-form-urlencoded")
      |> Plug.Conn.put_req_header("x-http-method-override", "DELETE")
      |> RequestCapture.call(@parser_opts)

    assert conn.method == "POST"
    assert conn.private.request_bin_original_method == "POST"
    assert {:ok, %{method: "POST"}} = Requests.extract_request_info(conn)
  end

  test "non-collector requests retain parser and method override behavior" do
    conn =
      "POST"
      |> Plug.Test.conn("/normal", "_method=DELETE&event=created")
      |> Plug.Conn.put_req_header("content-type", "application/x-www-form-urlencoded")
      |> RequestCapture.call(@parser_opts)
      |> Plug.MethodOverride.call(Plug.MethodOverride.init([]))

    assert conn.method == "DELETE"
    assert conn.body_params == %{"_method" => "DELETE", "event" => "created"}
    refute conn.private[:request_bin_collector]
  end

  test "HEAD retains its original method after Plug.Head changes routing method" do
    conn =
      "HEAD"
      |> Plug.Test.conn("/bin/example", "")
      |> RequestCapture.call(@parser_opts)
      |> Plug.Head.call(Plug.Head.init([]))

    assert conn.method == "GET"
    assert conn.private.request_bin_original_method == "HEAD"
    assert {:ok, %{method: "HEAD"}} = Requests.extract_request_info(conn)
  end

  test "rejects an oversized collector body without retaining partial bytes" do
    Application.put_env(:request_bin, :request_capture, max_body_bytes: 4)

    conn =
      "POST"
      |> Plug.Test.conn("/bin/example", "12345")
      |> RequestCapture.call(@parser_opts)

    assert conn.halted
    assert conn.status == 413
    refute Map.has_key?(conn.private, :request_bin_raw_body)
  end

  test "does not classify empty IDs, nested paths, or unsupported methods" do
    for {method, path} <- [{"POST", "/bin/"}, {"POST", "/bin/id/nested"}, {"OPTIONS", "/bin/id"}] do
      conn =
        method
        |> Plug.Test.conn(path, "body")
        |> Plug.Conn.put_req_header("content-type", "text/plain")
        |> RequestCapture.call(@parser_opts)

      refute conn.private[:request_bin_collector]
    end
  end
end
