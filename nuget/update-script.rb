require "json"
require "logger"
require "dependabot/credential"
require "dependabot/file_fetchers"
require "dependabot/file_parsers"
require "dependabot/update_checkers"
require "dependabot/file_updaters"
require "dependabot/pull_request_creator"
require "dependabot/config/file_fetcher"
require "dependabot/nuget"
require "json"
require "git"
require 'fileutils'
require 'uri'
require 'base64'
require 'open3'

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

def clone_branch(azure_access_token, azure_hostname, project_path, branch)
  b64_pat = Base64.strict_encode64(":#{azure_access_token}")

  # Git clone command with authorization header
  git_command = "git -c http.extraHeader='Authorization: Basic #{b64_pat}' clone --branch #{branch} https://#{azure_hostname}/#{project_path}"

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
end

# Package Manager for the project (should be 'nuget')
package_manager = ENV["PACKAGE_MANAGER"]

# Repository to create pull requests for
project_path = ENV["PROJECT_PATH"]

# Branch to look at and to target in a pull request
branch = ENV["BRANCH"]

# Azure DevOps Server hostname
azure_hostname = ENV["AZURE_HOSTNAME"]

# Azure DevOps PAT
azure_access_token = ENV["AZURE_ACCESS_TOKEN"]

# Github PAT
github_access_token = ENV["GITHUB_ACCESS_TOKEN"]

#project_path = "TFS2013_Migrated/PROD_EDOC4SP/_git/edoclink-service"

# Expected to be a JSON object passed to the underlying components
options = JSON.parse(options || "{}", {:symbolize_names => true})
puts "Running with options: #{options}"

# Setup Source and Credentials
credentials = [
  Dependabot::Credential.new(
    {
      "type" => "git_source",
      "host" => azure_hostname,
      "username" => "x-access-token",
      "password" => azure_access_token
    }
  )]

source = Dependabot::Source.new(
  provider: "azure",
  hostname: azure_hostname,
  api_endpoint: "https://#{azure_hostname}/",
  repo: project_path,
  directory: directory,
  branch: branch,
  )

# Clone the branch specified
clone_branch(azure_access_token, azure_hostname, project_path, branch)

##############################
# Fetch the dependency files #
##############################
# Define Source object
source = Dependabot::Source.new(
  provider: "azure",
  hostname: azure_hostname,
  api_endpoint: "https://#{azure_hostname}/",
  repo: project_path,
  branch: branch
)

puts "Fetching #{package_manager} dependency files for #{project_path} for all directories"
fetcher = Dependabot::FileFetchers.for_package_manager(package_manager).new(
  source: source,
  credentials: credentials,
  options: options)
dep_files = fetcher.files
commit = fetcher.commit
puts "--------------------------------------------------------"
puts "Dependency files fetched:"
dep_files.each do |file_x|
  puts "\t" + file_x.name
end
puts "--------------------------------------------------------"


##############################
# Parse the dependency files #
##############################
parser_class = Dependabot::Nuget::FileParser
parser = parser_class.new(dependency_files: dep_files, source: source, repo_contents_path: get_simplified_name(project_path))
dependencies = parser.parse

updated_deps_res = []
dependencies.select(&:top_level?).each do |dep|
  #########################################
  # Get update details for the dependency #
  #########################################
  puts "Getting update details for #{dep}"
  checker_class = Dependabot::Nuget::UpdateChecker
  checker = checker_class.new(
    dependency: dep,
    dependency_files: dep_files,
    credentials: credentials,
    options: options,
    #dependency_group: dependency_group
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
  dependency_files: dep_files,
  credentials: credentials,
  options: options,
  repo_contents_path: "/home/dependabot/dependabot-script/#{get_simplified_name(project_path)}"
)

#####################################
#       Generate Pull Request       #
#####################################
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
  base_commit: commit,
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