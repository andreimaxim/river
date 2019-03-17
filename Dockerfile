FROM ruby:2.6.2

# Bundler options
#
# The default value is taken from Heroku's build options, so they should be
# good enough for most cases. For development, be sure to set a blank default
# in docker-compose.override.yml.
ARG BUNDLER_OPTS="--without development:test \
                  --jobs 4 \
                  --deployment"

# The home directory of the application.
#
# During development, make sure that the APP_DIR environment variable is
# identical to the variable in your docker-compose.override.yml file,
# otherwise things might not work as expected.
ENV APP_DIR="/opt/river"

# Create a non-root user
RUN groupadd -r deploy \
        && useradd -m -r -g deploy deploy
RUN mkdir -p ${APP_DIR} \
        && chown -R deploy:deploy ${APP_DIR}

RUN apt-get update -qq \
        && apt-get install -y build-essential libpq-dev


# Move the the application folder to perform all the following tasks.
WORKDIR ${APP_DIR}
# Use the non-root user to perform any commands from this point forward.
#
# NOTE: The COPY command requires the --chown flag set otherwise it will
#       copy things as root.
USER deploy

# Copy the Gemfile and Gemfile.lock files so `bundle install` can run when the
# container is initialized.
#
# The added benefit is that Docker will cache this file and will not trigger
# the bundle install unless the Gemfile changed on the filesystem.
#
# NOTE: If the command fails because of the --chown flag, make sure you have a
#       recent stable version of Docker.
COPY --chown=deploy:deploy Gemfile* ./
RUN bundle install ${BUNDLER_OPTS}

# Copy over the files, in case the Docker Compose file does not specify a
# mount point.
COPY --chown=deploy:deploy . ./

# Setup the Rails app to run when the container is created, using the CMD as
# extra params that can be overriden via the command-line or docker-compose.yml
#
# In this case, we're prefixing everything with `jruby -G` so we don't have
# to do this every time we start the container or when running commands.
ENTRYPOINT ["bundle", "exec"]
CMD ["exe/river"]
