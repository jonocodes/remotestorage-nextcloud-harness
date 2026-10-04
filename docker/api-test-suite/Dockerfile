# The remoteStorage community's server test suite (PLAN-app.md AT11), pinned.
# Needs Ruby 2.7: its Gemfile pins json ~> 1.8.3, which does not build on Ruby 3.
# The full image already has git and compilers; its Debian release is archived, so no apt.
FROM ruby:2.7
ARG SUITE_COMMIT=55cc9a2bebefef5816663005ad7ef2107b8b89df
RUN git clone https://github.com/remotestorage/api-test-suite.git /suite \
 && cd /suite && git checkout "${SUITE_COMMIT}" \
 && gem install bundler -v 2.4.22 && bundle install
WORKDIR /suite
CMD ["rake", "test"]
