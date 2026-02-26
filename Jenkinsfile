pipeline {
    agent any

    parameters {
        string(name: 'GIT_REPO_URL', defaultValue: 'git@github-venturo:venturo-id/eragim-mobile-chat.git', description: 'Git repository URL')
        string(name: 'BRANCH', defaultValue: 'main', description: 'Branch to build')
        string(name: 'GIT_CREDENTIALS_ID', defaultValue: 'github-ssh-key', description: 'Jenkins credentials ID for Git')
        string(name: 'IMAGE_NAME', defaultValue: 'flutter-chat-web', description: 'Docker image name')
        string(name: 'DEPLOY_PORT', defaultValue: '3090', description: 'Host port to expose')
    }

    stages {
        stage('Pull Repository') {
            steps {
                script {
                    echo "Pulling repository: ${params.GIT_REPO_URL} (branch: ${params.BRANCH})"
                    git branch: params.BRANCH,
                        credentialsId: params.GIT_CREDENTIALS_ID,
                        url: params.GIT_REPO_URL
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                script {
                    echo "Building Docker image: ${params.IMAGE_NAME}"
                    sh "docker build -t ${params.IMAGE_NAME}:latest ."
                }
            }
        }

        stage('Deploy') {
            steps {
                script {
                    echo "Deploying to port ${params.DEPLOY_PORT}"

                    // Stop and remove existing container (if any)
                    sh """
                        docker stop ${params.IMAGE_NAME} || true
                        docker rm ${params.IMAGE_NAME} || true
                    """

                    // Run new container
                    sh """
                        docker run -d \
                            --name ${params.IMAGE_NAME} \
                            --restart unless-stopped \
                            -p ${params.DEPLOY_PORT}:80 \
                            ${params.IMAGE_NAME}:latest
                    """
                }
            }
        }

        stage('Clean') {
            steps {
                script {
                    echo "Cleaning up dangling Docker images..."
                    sh "docker image prune -f"
                }
            }
        }
    }

    post {
        success {
            echo "Deployment successful! App is running on port ${params.DEPLOY_PORT}"
        }
        failure {
            echo 'Deployment failed!'
        }
    }
}
