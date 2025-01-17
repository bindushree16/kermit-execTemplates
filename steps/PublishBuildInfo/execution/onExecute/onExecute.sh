PublishBuildInfo() {
  echo "[PublishBuildInfo] Authenticating with integration: $artifactoryIntegrationName"
  local rtUrl=$(eval echo "$"int_"$artifactoryIntegrationName"_url)
  local rtUser=$(eval echo "$"int_"$artifactoryIntegrationName"_user)
  local rtApiKey=$(eval echo "$"int_"$artifactoryIntegrationName"_apikey)
  retry_command jfrog rt config --url $rtUrl --user $rtUser --apikey $rtApiKey --interactive=false

  restore_run_state jfrog /tmp/jfrog

  local buildName="$buildName"
  local buildNumber="$buildNumber"
  if [ -z "$buildName" ] && [ -z "$buildNumber" ]; then
    if [ ! -z "$buildStepName" ]; then
      echo "[PublishBuildInfo] Using build name and number from build step: $buildStepName"
      buildName=$(eval echo "$""$buildStepName"_buildName)
      buildNumber=$(eval echo "$""$buildStepName"_buildNumber)
    fi
  fi

  local envInclude=""
  local envExclude=""
  local forceXrayScan=false
  local PublishBuildInfoCmd="jfrog rt bp $buildName $buildNumber"

  local stepConfiguration=$(cat $step_json_path | jq .step.configuration)
  if [ ! -z "$stepConfiguration" ] && [ "$stepConfiguration" != "null" ]; then
    envInclude=$(echo $stepConfiguration | jq -r .envInclude)
    envExclude=$(echo $stepConfiguration | jq -r .envExclude)
    forceXrayScan=$(echo $stepConfiguration | jq -r .forceXrayScan)
  fi

  if [ ! -z "$envInclude" ] && [ "$envInclude" != "null" ]; then
    PublishBuildInfoCmd="$PublishBuildInfoCmd --env-include $envInclude"
  fi

  if [ ! -z "$envExclude" ] && [ "$envExclude" != "null" ]; then
    PublishBuildInfoCmd="$PublishBuildInfoCmd --env-exclude $envExclude"
  fi

  echo "[PublishBuildInfo] Publishing build info $buildName/$buildNumber"
  retry_command $PublishBuildInfoCmd

  if [ "$forceXrayScan" == "true" ]; then
    echo "[PublishBuildInfo] Scanning build $buildName/$buildNumber"
    jfrog rt bs $buildName $buildNumber
  fi

  if [ ! -z "$outputBuildInfoResourceName" ]; then
    echo "[PublishBuildInfo] Updating output resource: $outputBuildInfoResourceName"
    write_output $outputBuildInfoResourceName buildName=$buildName buildNumber=$buildNumber
  fi

  save_run_state /tmp/jfrog/. jfrog
}

execute_command PublishBuildInfo
