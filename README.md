# Dev Container dotfiles

This repo contains some dotfiles I use in dev containers.

This includes a collection of git tools I created to improve my workflow.

## Setup

In VS Code

> Settings > Remote [Dev Container]

1. Set "Dotfiles > Repository" to `https://github.com/jordanmaguire/devcontainer_dotfiles`
2. Set "Dotfiles > Install Command" to `install_dev_container.sh`

Restart VS Code and the dotfiles will be installed in the path specified in "Dotfiles > Target Path" which is "~/dotfiles" by default.

You may lose this configuration when rebuilding your container.

Since this is git repo on a filesystem you can update the dotfiles directly in the dev container. Ensure you push your changes as the dotfiles are blown away semi-regularly by VS Code.
