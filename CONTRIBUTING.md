# Contributing to ranmaru

Thank you for your interest in contributing to ranmaru! This guide will help you
get started with building and developing the project.

## Prerequisites

- **OCaml 5.2+**: The project requires OCaml version 5.2 or higher
- **Dune 3.16+**: Build system for OCaml projects
- **Nix** (optional but recommended): For reproducible development environment

## Building the Project

### Option 1: Using Nix (Recommended)

If you have Nix with flakes enabled:

```bash
# Enter the development shell
nix develop

# Build the project
dune build

# Execute the program
dune exec ranmaru -- [ARGS]
```

### Option 2: Using Dune directly

If you have OCaml and the required dependencies installed:

```bash
# Install dependencies (using opam)
opam install --deps-only .

# Build the project
dune build

# Execute the program
dune exec ranmaru -- [ARGS]
```

### Option 3: Using the Nix package directly

```bash
# Build without entering the dev shell
nix build

# The binary will be available at ./result/bin/ranmaru
```

## Formatting the code

```bash
nix fmt  # Uses ocamlformat and other formatters
```

## Project Structure

- `ranmaru/` - Main source code directory
  - `main.ml` - Entry point
  - `*.ml`, `*.mli`: - Other imported files
  - `dune` - The executable package
- `dune-project` - Dune project configuration and dependencies
- `flake.nix` - Nix development environment and package definition

## Submitting Changes

1. Fork the repository.
2. Create a feature branch.
3. Make your changes following the project's coding style. See `.ocamlformat`
   and run `nix fmt`.
4. Ensure the project builds and the program works.
5. Format your code using the project's formatting tools.
6. Submit a pull request with a clear description of your changes.

## Getting Help

If you encounter issues or have questions:
- Check the existing issues in the repository
- Review the README.md for usage examples
- Feel free to open a new issue for bugs or feature requests
