# RequestBin

RequestBin is a tool for capturing and inspecting HTTP requests. It provides a simple interface to create bins where HTTP requests can be sent and inspected in real-time. It leverages Elixir's Phoenix framework for high-performance, scalable web applications.

## Overview

RequestBin consists of several components:

- **Bins**: Containers for capturing HTTP requests.
- **Requests**: HTTP requests that are captured by bins.
- **Oban Jobs**: Used for job processing, such as deleting old bins after a retention period.
- **Rate Limiting**: Controls the rate of incoming requests using the Hammer library.

The repository is organized into the following main directories and files:

- `lib/`: Contains the core application code, organized in modules.
- `config/`: Configuration files for different environments (development, test, production).
- `assets/`: Frontend assets managed by `esbuild` and `tailwind`.
- `test/`: Test files and support modules.

## Setup Instructions

To set up the project locally, follow these steps:

1. **Clone the repository**:

   ```bash
   git clone <repository_url>
   cd <repository_directory>
   ```

2. **Install dependencies**:

   ```bash
   mix deps.get
   ```

3. **Set up the database**:

   ```bash
   mix ecto.create
   mix ecto.migrate
   ```

4. **Start the Phoenix server**:

   ```bash
   mix phx.server
   ```

   You can also start the server using IEx for an interactive experience:

   ```bash
   iex -S mix phx.server
   ```

5. **Visit the application** in your browser at [`localhost:4000`](http://localhost:4000).

## Usage Examples

- **Create a RequestBin**:
  Once the server is running, navigate to `/bin` and click "Create a RequestBin". A unique bin URL will be generated for you to send HTTP requests to.

- **Inspect Requests**:
  After sending requests to a bin, you can inspect them by navigating to the bin's URL with the `/inspect` path. For example: `http://localhost:4000/bin/:id/inspect`.

## Features

- **Bin Management**: Create, inspect, and manage request bins.
- **Real-time Updates**: Bins are updated in real-time to show incoming requests.
- **Rate Limiting**: Protects the server from being overwhelmed with requests.
- **Scheduled Jobs**: Automatically delete bins after a retention period using Oban jobs.
- **Extensible Configuration**: Easily extend the application by modifying configuration in the `config/` directory.
- **Responsive Interface**: The web interface is built using Tailwind CSS for a clean and responsive design.

## Development Tools

- **Dockerfile**: A Dockerfile is included for containerized deployment and consistent runtime environments.
- **Pre-commit Hooks**: Set up for Git to ensure code quality using `gitleaks`.
- **Test Suite**: Comprehensive tests are included in the `test/` directory, using ExUnit and Phoenix's testing tools.

## Learn More

- **Official Phoenix Website**: [Phoenix Framework](https://www.phoenixframework.org/)
- **Phoenix Guides and Docs**:
  - [Guides](https://hexdocs.pm/phoenix/overview.html)
  - [Docs](https://hexdocs.pm/phoenix)
- **Community Forum**: [Elixir Forum](https://elixirforum.com/c/phoenix-forum)
- **Source Code**: [RequestBin on GitHub](https://github.com/phoenixframework/phoenix)

For deployment and production readiness, please refer to the [Phoenix Deployment Guides](https://hexdocs.pm/phoenix/deployment.html).
