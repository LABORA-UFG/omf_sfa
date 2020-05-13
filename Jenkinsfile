pipeline {
    environment {
        registry = "gustavo978/fibre-broker"
        registryCredential = '601e4fe0-c8e4-489d-84bb-4ed540d27f2c'
        dockerImage = ''
    }

    agent any
    stages {
        stage('Cloning our Git') {
            steps {
                checkout scm
            }
        }

        stage('Building our image') {
            steps{
                script {
                    dockerImage = docker.build registry + ":$BUILD_NUMBER"
                }
            }
        }

        stage('Deploy our image') {
            steps{
                script {
                    docker.withRegistry('', registryCredential) {
                        dockerImage.push()
                    }
                }
            }
        }

        stage('Cleaning up') {
            steps{
                sh "docker rmi $registry:$BUILD_NUMBER"
            }
        }
    }
}

