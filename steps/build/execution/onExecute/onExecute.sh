build() {
  echo "[build] Authenticating with integration: $artifactoryIntegrationName"
  local rtUrl=$(eval echo "$"int_"$artifactoryIntegrationName"_url)
  local rtUser=$(eval echo "$"int_"$artifactoryIntegrationName"_user)
  local rtApiKey=$(eval echo "$"int_"$artifactoryIntegrationName"_apikey)
  retry_command jfrog rt config --url $rtUrl --user $rtUser --apikey $rtApiKey --interactive=false

  payloadType=$step_payloadType
  buildName=$pipeline_name
  buildNumber=$run_number

  buildDir=$(eval echo "$"res_"$inputGitRepoResourceName"_resourcePath)/$dockerFileLocation
  echo "[build] Changing directory: $buildDir"
  pushd $buildDir
    if [ ! -z "$inputFileResourceName" ]; then
      filePath=$(eval echo "$"res_"$inputFileResourceName"_resourcePath)/*
      echo "[build] Copying files from: $filePath to: $(pwd)"
      # todo: remove -v
      cp -vr $filePath .
    fi

    if [ "$payloadType" == "docker" ]; then
      dockerFileLocation=$(jq -r ".step.setup.build.dockerFileLocation" $step_json_path)
      dockerFileName=$(jq -r ".step.setup.build.dockerFileName" $step_json_path)
      imageName=$(jq -r ".step.setup.build.imageName" $step_json_path)
      imageTag=$(jq -r ".step.setup.build.imageTag" $step_json_path)
      evalImageName=$(eval echo $imageName)
      evalImageTag=$(eval echo $imageTag)
      echo "[build] Building docker image: $evalImageName:$evalImageTag using Dockerfile: ${dockerFileName}"
      docker build -t $evalImageName:$evalImageTag -f ${buildDir}/${dockerFileName} .

      echo "[build] Adding build information to pipeline state"
      add_pipeline_variable buildStepName=${step_name}
      add_pipeline_variable ${step_name}_payloadType=${payloadType}
      add_pipeline_variable ${step_name}_buildNumber=${buildNumber}
      add_pipeline_variable ${step_name}_buildName=${buildName}
      add_pipeline_variable ${step_name}_isPromoted=false
      add_pipeline_variable ${step_name}_imageName=${evalImageName}
      add_pipeline_variable ${step_name}_imageTag=${evalImageTag}

    else
      echo "[build] Unsupported payloadType: $payloadType"
      exit 1
    fi
  popd

  jfrog rt bce $buildName $buildNumber
  save_run_state /tmp/jfrog/. jfrog
}

execute_command build
