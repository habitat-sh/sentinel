# The Sentinels

This is a github bot to allow management of repositories that contain open
source projects. It takes a list of maintainers for the repository, and
allows you to communicate with the bot about the status of a pull request.

* When a PR is opened, it will create a branch called `hypothetical-BRANCH`.
  This branch will contain the commits in your PR, rebased on top of master, as
  if they where merged. The status of the PR will be `In Progress`.
* The `hypothetical-BRANCH` will then be submitted to Travis CI for testing. The status of the PR will be 'In Testing', 
  with the URI of the travis job.
* A comment will be added to the PR that contains the commit that was on HEAD.
* If the test passes, the status on the PR will be updated to 'The Travis CI build passed'.
* If the test fails, the status on the PR will be updated to 'The Travis CI build failed'.

When someone on the committers list says:

```
@thesentinels approve
```

This bot will merge this PR. It will follow the following process:

* We will check the comment for the commit that was on HEAD. If HEAD has moved
  on, we will re-trigger the test phase, listed above.
* If the test is passing, we force push the hypothetical-BRANCH as BRANCH, then
  we merge the BRANCH.
* If the merge is successful, we delete hypothetical-BRANCH and BRANCH.


## Installation

Check out the source, run `bundle install`, then `bundle exec exe/dcob`.

This is also easy to run on heroku; clone the repo, push it to heroku, set the
environment variables and configure the webhook/access token. Viola!

## Configuration

The bot requires a toml configuration file with three settings:

```toml
[cfg]
login = "GITHUB_USERNAME"
access_token = "GITHUB_ACCESS_TOKEN"
secret_token = "SECRET_TOKEN"
```

These can also be set in your environment:

```
GITHUB_LOGIN
GITHUB_ACCESS_TOKEN
GITHUB_SECRET_TOKEN
```

The login is a github username; the access token is a personal access token
that has the Repo privilege. The secret token is the one you specify when you
add the bot as a webhook.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run
`rake spec` to run the tests. You can also run `bin/console` for an interactive
prompt that will allow you to experiment. Run `bundle exec dcob` to use the gem
in this directory, ignoring other installed copies of this gem.

To install this gem onto your local machine, run `bundle exec rake install`. To
release a new version, update the version number in `version.rb`, and then run
`bundle exec rake release`, which will create a git tag for the version, push
git commits and tags, and push the `.gem` file to
[rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at
https://github.com/habitat-sh/dcob. This project is intended to be a safe,
welcoming space for collaboration, and contributors are expected to adhere to
the [Contributor Covenant](contributor-covenant.org) code of conduct.


## License

The gem is available as open source under the terms of the [MIT
License](http://opensource.org/licenses/MIT).

foo
foo
foo
