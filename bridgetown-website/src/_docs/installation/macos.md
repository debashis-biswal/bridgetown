---
title: Bridgetown on macOS
hide_in_toc: true
category: installation
ruby_version: 3.0.1
order: 0
---

## Install Ruby

### With rbenv {#rbenv}

People often use [rbenv](https://github.com/rbenv/rbenv) to manage multiple
Ruby versions, which comes in handy when you need to run a specific Ruby version on a project.

```sh
# Install Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install rbenv and ruby-build
brew install rbenv

# Set up rbenv integration with your shell
rbenv init
```

Restart your terminal for changes to take effect.

Now you can install a new Ruby version. At the time of this writing, Ruby {{ page.ruby_version }} is the latest stable version. (Note: the installation may take a few minutes to complete.)

```sh
rbenv install {{ page.ruby_version }}
rbenv global {{ page.ruby_version }}

ruby -v
> ruby 3.0.1p64 (2021-04-05 revision 0fb782ee38) [arm64-darwin20]
```

(If for some reason `bundler` isn't installed automatically, just run `gem install bundler -N`)

And that's it! Check out [rbenv command references](https://github.com/rbenv/rbenv#command-reference) to learn how to use different versions of Ruby in your projects.

Now jump down to the [Install Node & Yarn](#node) section.

### With Homebrew {#brew}

You may install Ruby directly through [Homebrew](https://brew.sh).

```sh
# Install Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

brew install ruby
```

Add the brew ruby path to your shell config:

```sh
echo 'export PATH="/usr/local/opt/ruby/bin:$PATH"' >> ~/.zprofile
```

Then relaunch your terminal and check your updated Ruby setup:

```sh
which ruby
# /usr/local/opt/ruby/bin/ruby

ruby -v
```

Yay, we are now running current stable Ruby!

To set up Bundler for managing Rubygem dependencies as well as Ruby executable paths, run:

```sh
gem install --user-install bundler
```

Then append your path file with the following, replacing the `X.X` with the first two digits of your Ruby version.

```sh
echo 'export PATH="$HOME/.gem/ruby/X.X.0/bin:$PATH"' >> ~/.zprofile
```

Then relaunch your terminal and check that your gem paths point to your home directory by running:

```sh
gem env
```

And check that `SHELL PATH:` includes to a path to `~/.gem/ruby/X.X.0/bin`

{% rendercontent "docs/note" %}
Every time you update Ruby to a version with a different first two digits, you will need to update your path to match.

You will also need to add `--user-install` to any `gem install` statement you run.
{% endrendercontent %}

## Install Node & Yarn {#node}

Node is a JavaScript runtime that can execute on a server or development machine. Yarn
is a package manager for Node packages. You'll need Node and Yarn in order to install
and use Webpack, the frontend asset compiler that runs alongside Bridgetown. Yarn is
also used along with Concurrently and Browsersync to spin up a live-reload development
server.

The easiest way to install Node and Yarn is via Homebrew (which should already be installed after following the instructions above).

```sh
brew update
brew install node
brew install yarn
```

Then verify your installed versions:

```sh
node -v
yarn -v
```

{% render "docs/install/bridgetown" %}

{% render "docs/install/concurrently" %}
