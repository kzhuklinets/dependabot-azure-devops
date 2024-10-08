# typed: strict
# frozen_string_literal: true

require "dependabot/shared_helpers"

#
# This module auto installs the Azure Artifacts Credential Provider if any NuGet feeds are configured.
# Without it, package feed authentication is not passed down to the native helper tools (i.e. dotnet).
# See: https://github.com/tinglesoftware/dependabot-azure-devops/pull/1233 for more info.
#
# This module primarily fixes auth in .NET [Core] projects; .NET Framework project auth is handled by nuget.config.
# See: tinglesoftware/dependabot/overrides/nuget/nuget_config_credential_helpers.rb for more info.
#
# This credential provider is required for ALL private NuGet feeds, even if they are not hosted in Azure DevOps.
# See README.md (Credentials for private registries and feeds) for more details.
#

# TODO: Remove this once auth can be moved out to the "proxy" component, like dependabot-cli does

module TingleSoftware
  module Azure
    module ArtifactsCredentialProvider
      def self.install_if_private_nuget_feeds_are_configured
        return if private_nuget_feeds.empty?

        # Configure NuGet feed authentication
        ENV.store(
          "VSS_NUGET_EXTERNAL_FEED_ENDPOINTS",
          JSON.dump({
            "endpointCredentials" => private_nuget_feeds.map do |cred|
              token_parts = cred["token"]&.split(":", 2)&.reject(&:empty?) || []
              {
                "endpoint" => cred["url"],
                # Use username/password auth if provided, otherwise fallback to token auth.
                # This provides maximum compatibility with Azure DevOps, DevOps Server, and other third-party feeds.
                # When using DevOps PATs, the token is split into username/password parts; Username is not significant.
                # e.g. token "PAT:12345" --> { "username": "PAT", "password": "12345" }
                #            ":12345"    --> { "username": "unused", "password": "12345" }
                #            "12345"     --> { "username": "unused", "password": "12345" }
                #            ""          --> { "username": "unused", "password": "" }
                "username" => cred["username"] || token_parts.length > 1 ? token_parts.first : "unused",
                "password" => cred["password"] || token_parts.last
              }
            end
          })
        )

        # Install cred provider from https://github.com/microsoft/artifacts-credprovider
        puts ::Dependabot::SharedHelpers.run_shell_command(
          %(sh -c "$(curl -fsSL https://aka.ms/install-artifacts-credprovider.sh)"), allow_unsafe_shell_command: true
        )
      end

      def self.private_nuget_feeds
        JSON.parse(ENV.fetch("DEPENDABOT_EXTRA_CREDENTIALS", "[]")).select do |cred|
          cred["type"] == "nuget_feed" && (cred["username"] || cred["password"] || cred["token"])
        end
      end
    end
  end
end

TingleSoftware::Azure::ArtifactsCredentialProvider.install_if_private_nuget_feeds_are_configured
