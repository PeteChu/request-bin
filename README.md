# RequestBin

RequestBin is a real‑time HTTP request inspection tool built with Elixir and Phoenix. It lets you quickly create bins—temporary containers—into which you can send HTTP requests and then view detailed information about each request. This makes it ideal for debugging webhooks, testing API integrations, and monitoring client–server communication.

---

## Overview

RequestBin is composed of several key components:

- **Bins** – Lightweight containers for capturing and organizing HTTP requests.
- **Requests** – Incoming HTTP requests (including headers, body, query parameters, etc.) are stored and made available for inspection.
- **Oban Jobs** – Background jobs (using Oban) automatically delete bins after their retention period to keep the system clean.
- **Rate Limiting** – Requests are controlled with rate limiting (using Hammer) to protect your application.
- **Real-time Updates** – The bins update in real-time using Phoenix LiveView and PubSub broadcasts.
- **Responsive Web Interface** – Built with Phoenix and styled with Tailwind CSS to ensure a clean, modern look.

---

## Setup Instructions

Follow these steps to get RequestBin up and running on your local machine:

1. **Clone the Repository**

   ```bash
   git clone <repository_url>
   cd <repository_directory>
   ```

2. **Install Dependencies**

   Fetch both Elixir and JavaScript dependencies:

   ```bash
   mix deps.get
   ```

3. **Set Up the Database**

   Create and migrate the database:

   ```bash
   mix ecto.create
   mix ecto.migrate
   ```

4. **Install Frontend Assets**

   RequestBin uses esbuild and Tailwind for asset management. Install these dependencies if they aren’t already set up:

   ```bash
   mix assets.setup
   ```

5. **Start the Phoenix Server**

   Start your application with:

   ```bash
   mix phx.server
   ```

   Alternatively, you can launch an interactive session with:

   ```bash
   iex -S mix phx.server
   ```

6. **Access the Application**

   Visit [http://localhost:4000](http://localhost:4000) in your browser to see the application in action.

---

## Usage Examples

### Creating a RequestBin

- Navigate to `/bin` in your browser.
- Click the **"Create a RequestBin"** button.
- A unique URL will be generated where you can send HTTP requests using any tool (e.g., curl, Postman, or your browser).

### Inspecting Requests

- After sending requests to a bin, navigate to its inspection page, for example:

  ```
  http://localhost:4000/bin/<BIN_ID>/inspect
  ```

- The inspection page displays details such as:
  - HTTP method and path
  - Request headers (formatted with a readable, capitalized style)
  - Raw and parsed request bodies
  - Query parameters
  - Time since the request was received

### Example: Sending a Test Request with curl

```bash
curl -X POST http://localhost:4000/bin/<BIN_ID> \
  -H "Content-Type: application/json" \
  -d '{"key":"value"}'
```

As soon as the request is sent, it will appear in the RequestBin’s inspection view in real time.

---

## Features

- **Real-Time Request Inspection:** Live updates via Phoenix LiveView.
- **Temporary Bins:** Automatically expires bins after the specified retention period.
- **Rate Limiting:** Uses Hammer (backed by ETS) to protect against excessive traffic.
- **Flexible Configuration:** Environment-specific settings are managed in the `config/` directory.
- **Background Jobs:** Oban jobs handle automatic deletion of bins after expiration.
- **Responsive Interface:** Built using Tailwind CSS and Phoenix components for a modern look.
- **Extensible and Developer Friendly:** Structured with modular contexts for bins, requests, and utilities.

---

## Development Tools & Additional Information

- **Database Migrations:** Manage database changes with Ecto; see `lib/request_bin/release.ex` for production migration tasks.
- **Job Scheduling:** Oban is used for scheduling background deletion of expired bins.
- **Rate Limiting:** Integrated middleware in the endpoint to limit excessive incoming requests.
- **Testing:** Comprehensive test suite located in the `test/` directory.
- **Docker and Deployment:** A Dockerfile and deployment scripts help containerize and deploy RequestBin in different environments.
- **LiveDashboard & Mailbox Preview:** In development mode, access the LiveDashboard at `/dev/dashboard` and preview sent emails at `/dev/mailbox`.

For more detailed information about configuration or deployment, refer to the Phoenix documentation and the project’s configuration files in the `config/` directory.

---

## Learn More

- [Phoenix Framework Documentation](https://hexdocs.pm/phoenix/overview.html)
- [Elixir Official Website](https://elixir-lang.org)
- [Oban Documentation](https://hexdocs.pm/oban)
- [Hammer Rate Limiter Docs](https://hexdocs.pm/hammer)
- [Tailwind CSS Documentation](https://tailwindcss.com)
