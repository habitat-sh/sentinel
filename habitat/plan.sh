pkg_name=sentinel
pkg_origin=core
pkg_version=0.1.0
pkg_description="This is a github bot to manage Open Source Projects under the Habitat umbrella."
pkg_upstream_url=https://github.com/habitat-sh/sentinel
pkg_maintainer="The Habitat Maintainers <humans@habitat.sh>"
pkg_license=('MIT')
pkg_source=false
pkg_deps=(
  core/coreutils
  core/ruby
  core/git
  core/openssl
  core/gcc-libs
)
pkg_build_deps=(
  core/bundler
  core/cacerts
  core/coreutils
  core/rsync
  core/make
  core/cmake
  core/gcc
  core/pkg-config
)
pkg_bin_dirs=(bin)
pkg_svc_run="bin/sentinels -o 0.0.0.0"
pkg_expose=(4567)

do_download() {
  return 0
}

do_verify() {
  return 0
}

do_unpack() {
  return 0
}

do_build() {
  return 0
}

do_install () {
  # Create a Gemfile with what we need
  cat > Gemfile <<GEMFILE
source 'https://rubygems.org'
gem 'sentinel', path: '$pkg_prefix'
GEMFILE
  export BUNDLE_SILENCE_ROOT_WARNING=1 GEM_PATH
  GEM_PATH="$(pkg_path_for core/bundler)"
  cd $PLAN_CONTEXT/../
  rsync -vaP --exclude "cache" --exclude ".git" --exclude "vendor" --exclude "config.toml" --exclude "results" . $pkg_prefix
  bundle install --jobs "$(nproc)" --retry 5 --standalone \
    --path "$pkg_prefix/bundle" \
    --shebang=$(pkg_path_for ruby)/bin/ruby \
    --binstubs "$pkg_prefix/bin"
  pkg_lib_dirs+=$(find $pkg_prefix/bundle | grep '**/lib' | grep '\.so' | xargs dirname | sort -u)

  fix_interpreter "$pkg_prefix/bin/*" core/coreutils bin/env
}
