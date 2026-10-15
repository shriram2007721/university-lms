pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
    }

    environment {
        // CHANGE THIS to your lowercase Docker Hub username.
        IMAGE_REPO = 'docker.io/YOUR_DOCKERHUB_USERNAME/university-lms'
    }

    // For a local Windows Jenkins that GitHub cannot reach directly, poll GitHub.
    // Jenkins checks for changes approximately once per minute.
    triggers {
        pollSCM('H/1 * * * *')
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Check tools') {
            steps {
                powershell '''
                    $ErrorActionPreference = "Stop"
                    git --version
                    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
                    docker version
                    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
                    kubectl version --client
                    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
                '''
            }
        }

        stage('Build versioned Docker image') {
            steps {
                powershell '''
                    $image = "$($env:IMAGE_REPO):$($env:BUILD_NUMBER)"
                    $latest = "$($env:IMAGE_REPO):latest"
                    docker build --pull -t $image -t $latest .
                    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
                    Write-Host "Built image $image"
                '''
            }
        }

        stage('Smoke-test Docker image') {
            steps {
                powershell '''
                    $ErrorActionPreference = "Stop"
                    $image = "$($env:IMAGE_REPO):$($env:BUILD_NUMBER)"
                    docker rm -f lms-smoke-test 2>$null | Out-Null
                    docker run -d --name lms-smoke-test -p 18081:80 $image
                    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
                    $pageOk = $false
                    try {
                        for ($i = 0; $i -lt 10; $i++) {
                            try {
                                $response = Invoke-WebRequest -Uri 'http://localhost:18081' -UseBasicParsing -TimeoutSec 5
                                if ($response.StatusCode -eq 200 -and $response.Content -match 'University Learning Management Portal') {
                                    $pageOk = $true
                                    break
                                }
                            } catch { }
                            Start-Sleep -Seconds 2
                        }
                        if (-not $pageOk) {
                            docker logs lms-smoke-test
                            throw 'Smoke test failed: the portal homepage did not return the expected content.'
                        }
                        Write-Host 'Smoke test passed: the portal homepage returned HTTP 200.'
                    } finally {
                        docker rm -f lms-smoke-test 2>$null | Out-Null
                    }
                '''
            }
        }

        stage('Publish image to Docker Hub') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'dockerhub-creds', usernameVariable: 'DOCKERHUB_USER', passwordVariable: 'DOCKERHUB_TOKEN')]) {
                    powershell '''
                        $env:DOCKERHUB_TOKEN | docker login --username $env:DOCKERHUB_USER --password-stdin
                        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
                        $image = "$($env:IMAGE_REPO):$($env:BUILD_NUMBER)"
                        $latest = "$($env:IMAGE_REPO):latest"
                        docker push $image
                        if ($LASTEXITCODE -ne 0) { docker logout; exit 1 }
                        docker push $latest
                        if ($LASTEXITCODE -ne 0) { docker logout; exit 1 }
                        docker logout
                        Write-Host "Published version $image"
                    '''
                }
            }
        }

        stage('Deploy and health-check') {
            steps {
                // catchError marks this stage/build failed but lets the rollback-verification stage run.
                catchError(buildResult: 'FAILURE', stageResult: 'FAILURE') {
                    script {
                        try {
                            withCredentials([file(credentialsId: 'kubeconfig-file', variable: 'KUBECONFIG')]) {
                                powershell '''
                                    $ErrorActionPreference = "Stop"
                                    $image = "$($env:IMAGE_REPO):$($env:BUILD_NUMBER)"
                                    $yaml = Get-Content 'deployment.yaml' -Raw
                                    $rendered = $yaml.Replace('__IMAGE__', $image)
                                    Set-Content -Path 'deployment-rendered.yaml' -Value $rendered -Encoding utf8
                                    kubectl apply -f deployment-rendered.yaml
                                    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
                                    kubectl rollout status deployment/university-lms --timeout=90s
                                    if ($LASTEXITCODE -ne 0) { throw 'The new Kubernetes rollout did not become healthy.' }
                                '''
                            }
                            echo 'New release deployed successfully.'
                        } catch (err) {
                            echo "Deployment failed. Starting automatic rollback. Details: ${err}"
                            withCredentials([file(credentialsId: 'kubeconfig-file', variable: 'KUBECONFIG')]) {
                                powershell '''
                                    kubectl rollout history deployment/university-lms
                                    kubectl rollout undo deployment/university-lms
                                    if ($LASTEXITCODE -ne 0) { throw 'Automatic rollback command failed.' }
                                    kubectl rollout status deployment/university-lms --timeout=120s
                                    if ($LASTEXITCODE -ne 0) { throw 'The previous revision did not become healthy after rollback.' }
                                    kubectl get pods -l app=university-lms -o wide
                                '''
                            }
                            env.ROLLBACK_PERFORMED = 'true'
                            echo 'Rollback completed. The pipeline will remain FAILED so the bad release is visible in Jenkins.'
                            throw err
                        }
                    }
                }
            }
        }

        stage('Verify successful deployment') {
            when {
                expression { env.ROLLBACK_PERFORMED != 'true' }
            }
            steps {
                withCredentials([file(credentialsId: 'kubeconfig-file', variable: 'KUBECONFIG')]) {
                    powershell '''
                        $ErrorActionPreference = "Stop"
                        kubectl get deployment university-lms
                        kubectl get pods -l app=university-lms -o wide
                        kubectl get service university-lms-service
                        $response = Invoke-WebRequest -Uri 'http://localhost:30080' -UseBasicParsing -TimeoutSec 10
                        if ($response.StatusCode -ne 200 -or $response.Content -notmatch 'University Learning Management Portal') {
                            throw 'The NodePort website check failed.'
                        }
                        Write-Host 'SUCCESS: the Kubernetes application is reachable at http://localhost:30080.'
                    '''
                }
            }
        }

        stage('Verify restored stable release') {
            when {
                expression { env.ROLLBACK_PERFORMED == 'true' }
            }
            steps {
                withCredentials([file(credentialsId: 'kubeconfig-file', variable: 'KUBECONFIG')]) {
                    powershell '''
                        $ErrorActionPreference = "Stop"
                        kubectl get deployment university-lms
                        kubectl get pods -l app=university-lms -o wide
                        kubectl rollout history deployment/university-lms
                        $response = Invoke-WebRequest -Uri 'http://localhost:30080' -UseBasicParsing -TimeoutSec 10
                        if ($response.StatusCode -ne 200 -or $response.Content -notmatch 'University Learning Management Portal') {
                            throw 'Rollback ran, but the restored application did not pass the homepage check.'
                        }
                        Write-Host 'SUCCESS: previous stable release restored and website responds at http://localhost:30080.'
                    '''
                }
            }
        }
    }

    post {
        always {
            echo "Pipeline finished. Build number: ${env.BUILD_NUMBER}; result: ${currentBuild.currentResult}"
        }
    }
}
