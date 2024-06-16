# This script is designed to loop through all dependencies in a GHE, GitLab or
# Azure DevOps project, creating PRs where necessary.

require "dependabot/credential"
require "dependabot/file_fetchers"
require "dependabot/file_parsers"
require "dependabot/update_checkers"
require "dependabot/file_updaters"
require "dependabot/pull_request_creator"
require "dependabot/omnibus"
require "gitlab"
require "json"
require "git"
require 'fileutils'
require 'uri'
require 'base64'
require 'open3'


credentials = [
  Dependabot::Credential.new({
    "type" => "git_source",
    "host" => "github.com",
    "username" => "x-access-token",
    "password" => ENV["GITHUB_ACCESS_TOKEN"] # A GitHub access token with read access to public repos
  })
]

# Full name of the repo you want to create pull requests for.
repo_name = ENV["PROJECT_PATH"] # namespace/project

# Directory where the base dependency files are.
directory = ENV["DIRECTORY_PATH"] || "/"

# Branch to look at. Defaults to repo's default branch
branch = "azure-pipelines"

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
package_manager = ENV["PACKAGE_MANAGER"] || "bundler"

# Set of dependenct grouping rules
dependency_group = nil
if ENV["GROUPING_RULE"]
  rules = {
    "patterns" => [ENV["GROUPING_RULE"]],
    "dependency-type" => "production" # TODO: review this
  }
  dependency_group = Dependabot::DependencyGroup.new(
    name: "default",
    rules: rules,
    applies_to: "version-updates"
  )
end

# Expected to be a JSON object passed to the underlying components
options = JSON.parse(ENV["OPTIONS"] || "{}", {:symbolize_names => true})
puts "Running with options: #{options}"

if ENV["GITHUB_ENTERPRISE_ACCESS_TOKEN"]
  credentials << {
    "type" => "git_source",
    "host" => ENV["GITHUB_ENTERPRISE_HOSTNAME"], # E.g., "ghe.mydomain.com",
    "username" => "x-access-token",
    "password" => ENV["GITHUB_ENTERPRISE_ACCESS_TOKEN"] # A GHE access token with API permission
  }

  source = Dependabot::Source.new(
    provider: "github",
    hostname: ENV["GITHUB_ENTERPRISE_HOSTNAME"],
    api_endpoint: "https://#{ENV['GITHUB_ENTERPRISE_HOSTNAME']}/api/v3/",
    repo: repo_name,
    directory: directory,
    branch: branch,
  )
elsif ENV["GITLAB_ACCESS_TOKEN"]
  gitlab_hostname = ENV["GITLAB_HOSTNAME"] || "gitlab.com"

  credentials << {
    "type" => "git_source",
    "host" => gitlab_hostname,
    "username" => "x-access-token",
    "password" => ENV["GITLAB_ACCESS_TOKEN"] # A GitLab access token with API permission
  }

  source = Dependabot::Source.new(
    provider: "gitlab",
    hostname: gitlab_hostname,
    api_endpoint: "https://#{gitlab_hostname}/api/v4",
    repo: repo_name,
    directory: directory,
    branch: branch,
  )
elsif ENV["AZURE_ACCESS_TOKEN"]
  azure_hostname = ENV["AZURE_HOSTNAME"] || "dev.azure.com"

  #credentials << {
  #  "type" => "git_source",
  #  "host" => azure_hostname,
  #  "username" => "x-access-token",
  #  "password" => ENV["AZURE_ACCESS_TOKEN"]
  #}

  credentials = [
    Dependabot::Credential.new({
      "type" => "git_source",
      "host" => azure_hostname,
      "username" => "x-access-token",
      "password" => ENV["AZURE_ACCESS_TOKEN"]
    })
  ]

  source = Dependabot::Source.new(
    provider: "azure",
    repo: repo_name,
    directory: directory,
    branch: branch,
    hostname: azure_hostname,
    api_endpoint: "https://#{azure_hostname}/",
  )
elsif ENV["BITBUCKET_ACCESS_TOKEN"]
  bitbucket_hostname = ENV["BITBUCKET_HOSTNAME"] || "bitbucket.org"

  credentials << {
    "type" => "git_source",
    "host" => bitbucket_hostname,
    "username" => "x-token-auth",
    "token" => ENV["BITBUCKET_ACCESS_TOKEN"]
  }

  source = Dependabot::Source.new(
    provider: "bitbucket",
    hostname: bitbucket_hostname,
    api_endpoint: ENV["BITBUCKET_API_URL"] || "https://api.bitbucket.org/2.0/",
    repo: repo_name,
    directory: directory,
    branch: branch,
  )
elsif ENV["BITBUCKET_APP_USERNAME"] && ENV["BITBUCKET_APP_PASSWORD"]
  bitbucket_hostname = ENV["BITBUCKET_HOSTNAME"] || "bitbucket.org"

  credentials << {
    "type" => "git_source",
    "host" => bitbucket_hostname,
    "username" => ENV["BITBUCKET_APP_USERNAME"],
    "password" => ENV["BITBUCKET_APP_PASSWORD"]
  }

  source = Dependabot::Source.new(
    provider: "bitbucket",
    hostname: bitbucket_hostname,
    api_endpoint: ENV["BITBUCKET_API_URL"] || "https://api.bitbucket.org/2.0/",
    repo: repo_name,
    directory: directory,
    branch: branch,
  )
else
  source = Dependabot::Source.new(
    provider: "github",
    repo: repo_name,
    directory: directory,
    branch: branch,
  )
end

# Clone the repo for the current project
#git_username = `git remote set-url origin https://pedro.m.silva:#{ENV["PAT"]}@devops.aitec.pt/TFS2013_Migrated/PROD_EDOC4SP/_git/edoclink-service`
#git_username = `git config --global user.name "pedro.m.silva"`
#git_check = `git remote -v`
#git = `git -c http.extraheader="AUTHORIZATION: Basic #{ENV["PAT_B64"]}" clone https://devops.aitec.pt/TFS2013_Migrated/PROD_EDOC4SP/_git/edoclink-service`
#git = `git clone https://devops.aitec.pt/TFS2013_Migrated/PROD_EDOC4SP/_git/edoclink-service`
#git = `git clone https://pedro.m.silva:#{ENV["PAT_B64"]}@devops.aitec.pt/TFS2013_Migrated/PROD_EDOC4SP/_git/edoclink-service`

#global_opts = %w[-c http.extraheader="AUTHORIZATION: Basic #{ENV["PAT_B64"]}"]
#git = Git.clone("https://#{ENV["PAT_B64"]}@devops.aitec.pt/TFS2013_Migrated/PROD_EDOC4SP/_git/edoclink-service")
#git = `git clone https://{#{ENV["PAT_B64"]}}@devops.aitec.pt/TFS2013_Migrated/PROD_EDOC4SP/_git/edoclink-service`
#git = `git clone https://pedro.m.silva:#{ENV["AZURE_PWD"]}@devops.aitec.pt/TFS2013_Migrated/PROD_EDOC4SP/_git/edoclink-service`

## 2nd attempt
#repo_url = "https://devops.aitec.pt/TFS2013_Migrated/PROD_EDOC4SP/_git/edoclink-service"
#destination_folder = "edoclink-service"
#personal_access_token = ENV['PAT_B64']
#username = "pedro.m.silva"

#if repo_url.nil? || destination_folder.nil? || personal_access_token.nil? || username.nil?
#  puts "One or more required environment variables are missing."
#  exit 1
#end

# Ensure the destination folder does not already exist
#if Dir.exist?(destination_folder)
#  puts "Destination folder '#{destination_folder}' already exists. Please choose a different folder or delete the existing one."
#  exit 1
#end

# Encode username and PAT to handle special characters
#encoded_username = URI.encode_www_form_component(username)
#encoded_token = URI.encode_www_form_component(personal_access_token)

# Prepare the Git clone command
#uri = URI(repo_url)
#uri.userinfo = "#{encoded_username}:#{encoded_token}"
#clone_command = "git clone #{uri} #{destination_folder}"

# Execute the Git clone command
#puts "Cloning repository..."
#if system(clone_command)
#  puts "Repository cloned successfully to '#{destination_folder}'."
#else
#  puts "Failed to clone the repository."
#  exit 1
#end

# 3rd attempt
# Replace "yourPAT" with your actual PAT
my_pat = ENV["AZURE_ACCESS_TOKEN"]
b64_pat = Base64.strict_encode64(":#{my_pat}")

# Git clone command with authorization header
git_command = "git -c http.extraHeader='Authorization: Basic #{b64_pat}' clone https://devops.aitec.pt/TFS2013_Migrated/PROD_EDOC4SP/_git/edoclink-service"

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


##############################
# Fetch the dependency files #
##############################
puts "Fetching #{package_manager} dependency files for #{repo_name}"
fetcher = Dependabot::FileFetchers.for_package_manager(package_manager).new(
  source: source,
  credentials: credentials,
  options: options,
)

files = fetcher.files
puts files.inspect
commit = fetcher.commit
puts commit.inspect

##############################
# Parse the dependency files #
##############################
#puts "Parsing dependencies information"
#parser = Dependabot::FileParsers.for_package_manager(package_manager).new(
#  dependency_files: files,
#  source: source,
#  credentials: credentials,
#  options: options,
#)
parser_class = Dependabot::Nuget::FileParser
parser = parser_class.new(dependency_files: files, source: source, repo_contents_path: "edoclink-service")

dependencies = parser.parse
puts dependencies.inspect

# Create updated_files array
updated_files = []
updated_deps_res = []

dependencies.select(&:top_level?).each do |dep|
  #########################################
  # Get update details for the dependency #
  #########################################
  puts "Getting update details for #{dep}"
  #checker = Dependabot::UpdateCheckers.for_package_manager(package_manager).new(
  #  dependency: dep,
  #  dependency_files: files,
  #  credentials: credentials,
  #  options: options,
  #  dependency_group: dependency_group
  #)
  checker_class = Dependabot::Nuget::UpdateChecker
  checker = checker_class.new(
    dependency: dep,
    dependency_files: files,
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

  #updated_deps_res = (updated_deps_res << updated_deps).flatten!
  updated_deps_res = updated_deps

  #####################################
  # Generate updated dependency files #
  #####################################
  print "  - Updating #{dep.name} (from #{dep.version})…"
  #updater = Dependabot::FileUpdaters.for_package_manager(package_manager).new(
  #  dependencies: updated_deps,
  #  dependency_files: files,
  #  credentials: credentials,
  #  options: options,
  #)
  updater_class = Dependabot::Nuget::FileUpdater
  updater = updater_class.new(
    dependencies: updated_deps,
    dependency_files: files,
    credentials: credentials,
    options: options,
    repo_contents_path: "/home/dependabot/dependabot-script/edoclink-service"
  )

  updated_files = (updated_files << updater.updated_dependency_files).flatten!

  ########################################
  # Create a pull request for the update #
  ########################################
  #assignee = (ENV["PULL_REQUESTS_ASSIGNEE"] || ENV["GITLAB_ASSIGNEE_ID"])&.to_i
  #assignees = assignee ? [assignee] : assignee
  #pr_creator = Dependabot::PullRequestCreator::Azure.new(
  #  source: source,
  #  base_commit: commit,
  #  #dependencies: updated_deps,
  #  files: updated_files,
  #  credentials: credentials,
  #  assignees: assignees,
  #  author_details: { name: "Dependabot", email: "no-reply@github.com" },
  #  #label_language: true,
  #)
  puts "#############################################################################################"
  puts updated_files
  puts "#############################################################################################"
  puts updated_deps_res
  puts "#############################################################################################"
 
  #pull_request = pr_creator.create
  #puts " submitted"

  #next unless pull_request

  # Enable GitLab "merge when pipeline succeeds" feature.
  # Merge requests created and successfully tested will be merge automatically.
  #if ENV["GITLAB_AUTO_MERGE"]
  #  g = Gitlab.client(
  #    endpoint: source.api_endpoint,
  #    private_token: ENV["GITLAB_ACCESS_TOKEN"]
  #  )
  #  g.accept_merge_request(
  #    source.repo,
  #    pull_request.iid,
  #    merge_when_pipeline_succeeds: true,
  #    should_remove_source_branch: true
  #  )
  #end
end

# Debug classes:
puts "Files class: #{updated_files.class}"
puts "Files content: #{updated_files.inspect}"
updated_files.each do |x|
  puts "File class: #{x.class}"
  puts "File content: #{x.inspect}"
end

#
# Create a list of updated files
#
########################################
# Create a pull request for the update #
########################################
assignee = (ENV["PULL_REQUESTS_ASSIGNEE"] || ENV["GITLAB_ASSIGNEE_ID"])&.to_i
assignees = assignee ? [assignee] : assignee
#pr_creator = Dependabot::PullRequestCreator.new(
#  source: source,
#  base_commit: commit,
#  dependencies: updated_deps_res,
#  files: updated_files,
#  credentials: credentials,
#  assignees: assignees,
#  author_details: { name: "Dependabot", email: "no-reply@github.com" },
#  label_language: true,
#)
pr_creator = Dependabot::PullRequestCreator::Azure.new(
 source: source,
 branch_name: "azure_pipelines",
 base_commit: commit,
 credentials: credentials,
 files: updated_files,
 commit_message: "test dependabot commit",
 pr_description: "test dependabot PR",
 pr_name: "dependabot versions bump",
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
 reviewers: nil,
 assignees: assignees,
 work_item: nil
)

begin
  puts "Calling get_api_url"
  target_api_url = pr_creator.get_api_url
  puts "target_api_url: #{target_api_url}"
rescue => e
  puts "An error occurred: #{e.message}"
  puts e.backtrace.join("\n")
end

#pull_request = pr_creator.create
#puts "Calling get_api_url"
#target_api_url = pr_creator.get_api_url
#puts "URL: #{target_api_url}"
#puts pull_request.body
puts " submitted"

#next unless pull_request
#
#Enable GitLab "merge when pipeline succeeds" feature.
#Merge requests created and successfully tested will be merge automatically.
#if ENV["GITLAB_AUTO_MERGE"]
#  g = Gitlab.client(
#    endpoint: source.api_endpoint,
#    private_token: ENV["GITLAB_ACCESS_TOKEN"]
#  )
#  g.accept_merge_request(
#    source.repo,
#    pull_request.iid,
#    merge_when_pipeline_succeeds: true,
#    should_remove_source_branch: true
#  )
#end

puts "Done"
