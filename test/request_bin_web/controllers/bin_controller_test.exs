defmodule RequestBinWeb.BinControllerTest do
  use RequestBinWeb.ConnCase, async: false

  alias RequestBin.RequestsRepo

  test "JSON collection ignores Accept and persists exact bytes", %{conn: conn} do
    bin = bin_fixture()
    body = ~s({ "event" : "created" })

    conn = collect(conn, bin.id, body, "application/json", accept: "text/plain")

    assert response(conn, 200) == "ok"
    assert [request] = RequestsRepo.list_requests_by_bin(bin.id)
    assert request.body_raw == body
    assert request.body_parsed == %{"event" => "created"}
  end

  test "malformed and top-level JSON are persisted safely", %{conn: conn} do
    malformed_bin = bin_fixture()
    array_bin = bin_fixture()

    assert collect(conn, malformed_bin.id, "{broken", "application/json").status == 200
    assert [malformed] = RequestsRepo.list_requests_by_bin(malformed_bin.id)
    assert malformed.body_raw == "{broken"
    assert malformed.body_parsed == %{"_parse_error" => "invalid_json"}

    conn = Phoenix.ConnTest.build_conn()
    assert collect(conn, array_bin.id, "[1,2]", "application/event+json").status == 200
    assert [array] = RequestsRepo.list_requests_by_bin(array_bin.id)
    assert array.body_parsed == %{"_json" => [1, 2]}
  end

  test "URL-encoded and text inputs preserve their exact bodies", %{conn: conn} do
    form_bin = bin_fixture()
    text_bin = bin_fixture()

    form = "event=created&source=integration"
    assert collect(conn, form_bin.id, form, "application/x-www-form-urlencoded").status == 200
    assert [request] = RequestsRepo.list_requests_by_bin(form_bin.id)
    assert request.body_raw == form
    assert request.body_parsed == %{"event" => "created", "source" => "integration"}

    conn = Phoenix.ConnTest.build_conn()
    text = <<0, 255, 10, 65>>
    assert collect(conn, text_bin.id, text, "application/octet-stream").status == 200
    assert [request] = RequestsRepo.list_requests_by_bin(text_bin.id)
    assert request.body_raw == text
    assert request.body_parsed == %{}
  end

  test "multipart input persists the wire bytes without upload structs", %{conn: conn} do
    bin = bin_fixture()

    body =
      "--boundary\r\nContent-Disposition: form-data; name=\"event\"\r\n\r\ncreated\r\n--boundary--\r\n"

    assert collect(conn, bin.id, body, "multipart/form-data; boundary=boundary").status == 200
    assert [request] = RequestsRepo.list_requests_by_bin(bin.id)
    assert request.body_raw == body
    assert request.body_parsed == %{}
  end

  test "method override input persists the original POST", %{conn: conn} do
    bin = bin_fixture()
    body = "_method=DELETE&event=created"

    assert collect(conn, bin.id, body, "application/x-www-form-urlencoded").status == 200
    assert [request] = RequestsRepo.list_requests_by_bin(bin.id)
    assert request.method == "POST"
  end

  test "a nonexistent bin returns 404 without persistence", %{conn: conn} do
    id = Ecto.UUID.generate()

    conn = collect(conn, id, "payload", "text/plain")

    assert response(conn, 404) == "bin not found"
    assert RequestsRepo.list_requests_by_bin(id) == []
  end

  test "an oversized body returns 413 without persistence", %{conn: conn} do
    original = Application.fetch_env!(:request_bin, :request_capture)
    Application.put_env(:request_bin, :request_capture, max_body_bytes: 4)
    on_exit(fn -> Application.put_env(:request_bin, :request_capture, original) end)

    bin = bin_fixture()
    conn = collect(conn, bin.id, "12345", "text/plain")

    assert response(conn, 413) == "request body too large"
    assert RequestsRepo.list_requests_by_bin(bin.id) == []
  end

  test "browser requests retain normal parsing and method override", %{conn: conn} do
    conn =
      conn
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> post("/", "_method=DELETE")

    assert conn.method == "DELETE"
    refute conn.private[:request_bin_collector]
  end

  defp collect(conn, bin_id, body, content_type, opts \\ []) do
    conn =
      conn
      |> put_req_header("content-type", content_type)
      |> put_req_header("accept", Keyword.get(opts, :accept, "*/*"))

    post(conn, "/bin/#{bin_id}", body)
  end
end
