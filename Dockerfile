#FROM ghcr.io/dependabot/dependabot-core:0.215.0
#FROM ghcr.io/dependabot/dependabot-core:latest

# nuget
#FROM docker.io/pedroms214/group_dependabot:latest
# npm
FROM docker.io/pedroms214/group_dependabot_npm:latest

ARG CODE_DIR=/home/dependabot/dependabot-script
RUN mkdir -p ${CODE_DIR}
COPY --chown=dependabot:dependabot Gemfile ${CODE_DIR}/
WORKDIR ${CODE_DIR}

RUN bundle config set --local path "vendor" \
  && bundle install --jobs 4 --retry 3

COPY --chown=dependabot:dependabot . ${CODE_DIR}

CMD ["bundle", "exec", "ruby", "./npm/update-script.rb"]
