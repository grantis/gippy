# Gippy CLI

Gippy is a secure, native command-line interface (CLI) built in Swift for
interacting with OpenAI’s ChatGPT API. It supports an easy configuration
flow for your API key, local storage in a config file, and optional debug
logging.

## FEATURES
- Native Swift CLI – No Python or other runtime dependencies required.
- Async/Await – Modern Swift concurrency for clean, readable async code.
- Easy Configuration – A "configure" subcommand guides you through setting
  your API key.
- Environment Variable Fallback – If `OPENAI_API_KEY` is set, Gippy will use
  it automatically.
- Debug Mode – Pass "--debug" to see detailed logs, including request /
  response data.

## GETTING STARTED

1. Clone the Repository

    git clone https://github.com/yourusername/GippyCLI.git
    cd GippyCLI

2. Build and Install

   This project uses Swift Package Manager and provides a convenient Makefile.
   Ensure you have Swift 5.7 or later installed on macOS 12+.

    make build      # Builds the project
    make install    # Copies the binary to /usr/local/bin/gippy (requires sudo)

   Now the command "gippy" is available anywhere in your terminal.

## CONFIGURATION

### Method A: Configure Subcommand

    gippy configure

You’ll be prompted to enter your OpenAI API key (e.g., sk-...).
By default, it saves your key to ~/.gippy/config.json.

If you want to validate the key immediately (slightly more secure), use:

    gippy configure --test-key

This performs a quick request to ensure your key is valid, then stores it.

### Method B: Environment Variable
Alternatively, you can set OPENAI_API_KEY in your shell profile:

    echo 'export OPENAI_API_KEY="sk-xxxxxxxxxxx"' >> ~/.zshrc
    source ~/.zshrc

Gippy will automatically pick it up.

## USAGE

After installing and configuring:

Basic Query:

    gippy "Explain quantum entanglement in simple terms."

Debug Mode:

    gippy --debug "Explain the debugging process in Swift."

This prints detailed logs about the request headers, body, and response.

Help / Subcommands:

    gippy --help
    gippy configure --help
