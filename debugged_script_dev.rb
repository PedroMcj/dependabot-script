# Taken from dry-run script
require "etc"
unless Etc.getpwuid(Process.uid).name == "dependabot" || ENV["ALLOW_DRY_RUN_STANDALONE"] == "true"
  puts <<~INFO
    bin/dry-run.rb is only supported in a development container.

    Please use bin/docker-dev-shell first.
  INFO
  exit 1
end

$LOAD_PATH << "../bundler/lib"
$LOAD_PATH << "../cargo/lib"
$LOAD_PATH << "../common/lib"
$LOAD_PATH << "../composer/lib"
$LOAD_PATH << "../devcontainers/lib"
$LOAD_PATH << "../docker/lib"
$LOAD_PATH << "../elm/lib"
$LOAD_PATH << "../git_submodules/lib"
$LOAD_PATH << "../github_actions/lib"
$LOAD_PATH << "../go_modules/lib"
$LOAD_PATH << "../gradle/lib"
$LOAD_PATH << "../hex/lib"
$LOAD_PATH << "../maven/lib"
$LOAD_PATH << "../npm_and_yarn/lib"
$LOAD_PATH << "../nuget/lib"
$LOAD_PATH << "../python/lib"
$LOAD_PATH << "../pub/lib"
$LOAD_PATH << "../swift/lib"
$LOAD_PATH << "../terraform/lib"

updater_image_gemfile = File.expand_path("../dependabot-updater/Gemfile", __dir__)
updater_repo_gemfile = File.expand_path("../updater/Gemfile", __dir__)

ENV["BUNDLE_GEMFILE"] ||= File.exist?(updater_image_gemfile) ? updater_image_gemfile : updater_repo_gemfile

require "bundler"
Bundler.setup

require "optparse"
require "json"
#require "debug"
require "logger"
#require "dependabot/logger"
#require "stackprof"

#Dependabot.logger = Logger.new($stdout)

require "dependabot/credential"
require "dependabot/file_fetchers"
require "dependabot/file_parsers"
require "dependabot/update_checkers"
require "dependabot/file_updaters"
require "dependabot/pull_request_creator"
require "dependabot/pull_request_updater"
require "dependabot/config/file_fetcher"
require "dependabot/simple_instrumentor"

require "dependabot/bundler"
require "dependabot/cargo"
require "dependabot/composer"
require "dependabot/devcontainers"
require "dependabot/docker"
require "dependabot/elm"
require "dependabot/git_submodules"
require "dependabot/github_actions"
require "dependabot/go_modules"
require "dependabot/gradle"
require "dependabot/hex"
require "dependabot/maven"
require "dependabot/npm_and_yarn"
require "dependabot/nuget"
require "dependabot/python"
require "dependabot/pub"
require "dependabot/swift"
require "dependabot/terraform"
require "json"
require "git"
require 'fileutils'
require 'uri'
require 'base64'
require 'open3'

#directories = ["/src/edoclink.Core.Application", "/src/edoclink.Core.Domain"]
#directories = ["/src/edoclink.Infrastructure"]
directories = ["/src/edoclink.Infrastructure",
               "/src/edoclink.Core.Application",
               "/src/edoclink.Core.Domain",
               "/src/edoclink.Infrastructure.LegacyPdfConverter",
               "/src/edoclink.Infrastructure.SQLServer",
               "/src/edoclink.SDK",
               "/src/edoclink.Shared",
               "/src/edoclink.WebAPI"]

# debug variables
github_access_token = ""
project_path = "TFS2013_Migrated/PROD_EDOC4SP/_git/edoclink-service"
directory_path = nil
branch = "azure-pipelines"
package_manager = "nuget"
grouping_rule = "*"
options = "{}"
github_enterprise_access_token = nil
github_enterprise_hostname = nil
gitlab_hostname = nil
gitlab_access_token = nil
azure_access_token = ""
azure_hostname = "devops.aitec.pt"
bitbucket_access_token = nil
bitbucket_api_url = nil
bitbucket_app_username = nil
bitbucket_app_password = nil
bitbucket_hostname = nil
pull_requests_assignee = nil
gitlab_assignee_id = nil
gitlab_auto_merge = false

# AUX FUNCTIONS
def truncate(string, max)
  string.length > max ? "#{string[0...max]}..." : string
end

def get_simplified_name(string)
  tokens = string.split('/')
  tokens.last
end

def reduce_commit_message(string)
  tokens = string.split("\n\n")
  tokens.shift
  tokens.join("\n\n")
end

credentials = [
  Dependabot::Credential.new({
    "type" => "git_source",
    "host" => "github.com",
    "username" => "x-access-token",
    "password" => github_access_token # A GitHub access token with read access to public repos
  })
]

# Full name of the repo you want to create pull requests for.
repo_name = project_path # namespace/project

# Directory where the base dependency files are.
directory = directory_path || "/"

# Branch to look at. Defaults to repo's default branch
branch = branch

# Name of the package manager you'd like to do the update for. Options are:
# - bundler
# - pip (includes pipenv)
# - npm_and_yarn
# - maven
# - gradle
# - cargo
# - hex
# - composer
# - nuget
# - dep
# - go_modules
# - elm
# - submodules
# - docker
# - terraform
package_manager = package_manager || "bundler"

# Set of dependenct grouping rules
dependency_group = nil
if grouping_rule
  rules = {
    "patterns" => [grouping_rule],
    "dependency-type" => "production" # TODO: review this
  }
  dependency_group = Dependabot::DependencyGroup.new(
    name: "default",
    rules: rules,
    applies_to: "version-updates"
  )
end

# Expected to be a JSON object passed to the underlying components
options = JSON.parse(options || "{}", {:symbolize_names => true})
puts "Running with options: #{options}"

# Setup Source and Credentials
azure_hostname = azure_hostname || "dev.azure.com"

credentials = [
  Dependabot::Credential.new({
    "type" => "git_source",
    "host" => azure_hostname,
    "username" => "x-access-token",
    "password" => azure_access_token
  })
]

source = Dependabot::Source.new(
  provider: "azure",
  hostname: azure_hostname,
  api_endpoint: "https://#{azure_hostname}/",
  repo: repo_name,
  directory: directory,
  branch: branch,
)

# Replace "yourPAT" with your actual PAT
my_pat = azure_access_token
b64_pat = Base64.strict_encode64(":#{my_pat}")

# Git clone command with authorization header
git_command = "git -c http.extraHeader='Authorization: Basic #{b64_pat}' clone --branch #{branch} https://devops.aitec.pt/TFS2013_Migrated/PROD_EDOC4SP/_git/edoclink-service"

# Execute the git command
Open3.popen3(git_command) do |stdin, stdout, stderr, wait_thr|
  exit_status = wait_thr.value
  if exit_status.success?
    puts stdout.read
  else
    puts stderr.read
    exit exit_status.to_i
  end
end

# Create updated_files array
updated_files = nil
updated_deps_res = []
commit_res = nil

dep_files_res = []
commit_res = nil
source = Dependabot::Source.new(
  provider: "azure",
  hostname: azure_hostname,
  api_endpoint: "https://#{azure_hostname}/",
  repo: repo_name,
  #directory: directory_x,
  #directories: directories,
  branch: branch
)

##############################
# Fetch the dependency files #
##############################
puts "Fetching #{package_manager} dependency files for #{repo_name} for all directories"
fetcher = Dependabot::FileFetchers.for_package_manager(package_manager).new(
  source: source,
  credentials: credentials,
  options: options,
)
dep_files_res = fetcher.files
commit_res = fetcher.commit
puts "--------------------------------------------------------"
puts "Dependency files fetched:"
dep_files_res.each do |file_x|
  puts "\t" + file_x.name
end
puts "--------------------------------------------------------"


##############################
# Parse the dependency files #
##############################
parser_class = Dependabot::Nuget::FileParser
parser = parser_class.new(dependency_files: dep_files_res, source: source, repo_contents_path: "edoclink-service")

dependencies = parser.parse
puts dependencies.inspect

counter = 0
old_commit = nil
base_commit = nil
pull_request_id = nil
dependencies.select(&:top_level?).each do |dep|
  #########################################
  # Get update details for the dependency #
  #########################################
  puts "Getting update details for #{dep}"
  checker_class = Dependabot::Nuget::UpdateChecker
  checker = checker_class.new(
    dependency: dep,
    dependency_files: dep_files_res,
    credentials: credentials,
    options: options,
    dependency_group: dependency_group
  )

  next if checker.up_to_date?
  puts "\tis not up to date"
  requirements_to_unlock =
    if !checker.requirements_unlocked_or_can_be?
      if checker.can_update?(requirements_to_unlock: :none) then :none
      else :update_not_possible
      end
    elsif checker.can_update?(requirements_to_unlock: :own) then :own
    elsif checker.can_update?(requirements_to_unlock: :all) then :all
    else :update_not_possible
    end

  next if requirements_to_unlock == :update_not_possible
  puts "\tupdate is possible"
  updated_deps = checker.updated_dependencies(
    requirements_to_unlock: requirements_to_unlock
  )

  updated_deps_res = (updated_deps_res << updated_deps).flatten!
end

#####################################
# Generate updated dependency files #
#####################################
updater_class = Dependabot::Nuget::FileUpdater
updater = updater_class.new(
  dependencies: updated_deps_res,
  dependency_files: dep_files_res,
  credentials: credentials,
  options: options,
  repo_contents_path: "/home/dependabot/dependabot-script/edoclink-service"
)
updated_files = updated_files ? (updated_files << updater.updated_dependency_files).flatten! : updater.updated_dependency_files

# Create a new branch namer class
namer = Dependabot::PullRequestCreator::BranchNamer.new(
  dependencies: updated_deps_res,
  files: updater.updated_dependency_files,
  target_branch: "azure-pipelines",
  separator: "/",
  prefix: "dependabot",
  max_length: nil,
  dependency_group: nil,
  includes_security_fixes: false
)

# Add a authenticated github token to the message builder (in case the number of API requests necessary is above 60)
credentials_github = Dependabot::Credential.new(
  {
              "type" => "git_source",
              "host" => "github.com",
              "username" => "x-access-token",
              "password" => github_access_token # A GitHub access token with read access to public repos
            })

# Create a message builder class
message_builder = Dependabot::PullRequestCreator::MessageBuilder.new(
  source: source,
  dependencies: updated_deps_res,
  files: updater.updated_dependency_files,
  credentials: [credentials_github],
  pr_message_header: nil,
  pr_message_footer: nil,
  commit_message_options: nil,
  pr_message_max_length: 3999,
  pr_message_encoding: nil
)

assignee = (pull_requests_assignee || gitlab_assignee_id)&.to_i
assignees = assignee ? [assignee] : assignee
pr_creator = Dependabot::PullRequestCreator::Azure.new(
  source: source,
  branch_name: namer.new_branch_name,
  base_commit: commit_res,
  credentials: credentials,
  files: updater.updated_dependency_files,
  commit_message: "Bump project dependency versions",  # TODO: review this. what should the commit message be?
  pr_description: truncate(reduce_commit_message(message_builder.commit_message), 3996),
  pr_name: message_builder.pr_name,
  author_details: { name: "Dependabot", email: "no-reply@github.com" },
  labeler: Dependabot::PullRequestCreator::Labeler.new(
    source: source,
    custom_labels: nil,
    credentials: credentials,
    dependencies: updated_deps_res,
    includes_security_fixes: false,
    label_language: true,
    automerge_candidate: false
  ),
  #reviewers: ["alexandre.frazao@linkconsulting.com", "filipe.correia@linkconsulting.com"],
  reviewers: nil,
  assignees: assignees,
  work_item: nil
)

begin
  pull_request = pr_creator.create
  puts "--------------------------------------------------------"
  puts pull_request&.body
  puts "PR submitted"
  puts "--------------------------------------------------------"
  puts "Commit Message: " + message_builder.commit_message
  puts "PR Message: " + message_builder.pr_message
  puts "PR Name: " + message_builder.pr_name
rescue => e
  puts "An error occurred: #{e.message}"
  puts e.backtrace.join("\n")
end

puts "Done"
