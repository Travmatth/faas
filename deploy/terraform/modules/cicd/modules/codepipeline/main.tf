variable "github_repo" {}
variable "codepipeline_artifact_bucket" {}
variable "codedeploy" {}
variable "codebuild_logging_bucket" {}
variable "dynamodb_lock_state_table" {}
variable "codebuild_project" {}
variable "webhook_secret" {}
variable "github_oauth_token" {}

resource "aws_codepipeline" "codepipeline" {
  name     = "qaas-codepipeline"
  role_arn = aws_iam_role.codepipeline_role.arn

  artifact_store {
    location = var.codepipeline_artifact_bucket.bucket
    type     = "S3"
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "ThirdParty"
      provider         = "GitHub"
      version          = "1"
      output_artifacts = ["source_artifact"]
      configuration = {
        Owner                = "travmatth-org"
        Repo                 = var.github_repo.name
        Branch               = "master"
        OAuthToken           = var.github_oauth_token
        PollForSourceChanges = false
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["source_artifact"]
      output_artifacts = ["build_log"]
      version          = "1"

      configuration = {
        ProjectName = var.codebuild_project.name
      }
    }
  }

  # stage {
  #   name = "Manual_Approval"

  #   action {
  #     name      = "Manual-Approval"
  #     category  = "Approval"
  #     owner     = "AWS"
  #     provider  = "Manual"
  #     version   = "1"
  #   }
  # }

  # https://docs.aws.amazon.com/codepipeline/latest/userguide/reference-pipeline-structure.html
  stage {
    name = "Deploy"

    action {
      name             = "Deploy"
      category         = "Deploy"
      owner            = "AWS"
      provider         = "S3"
      version          = "1"
      input_artifacts  = ["build_log"]
      output_artifacts = []
      configuration = {
        BucketName = var.codepipeline_artifact_bucket.bucket
        Extract    = true
        CannedACL  = "private"
        ObjectKey  = "packer/logs/build-{datetime}.log"
      }
    }
  }
}

output "codepipeline" {
  value = aws_codepipeline.codepipeline
}

resource "aws_codepipeline_webhook" "qaas" {
  name            = "qaas-codepipeline-webhook"
  authentication  = "GITHUB_HMAC"
  target_action   = "Source"
  target_pipeline = aws_codepipeline.codepipeline.name

  authentication_configuration {
    secret_token = var.webhook_secret
  }

  filter {
    json_path    = "$.ref"
    match_equals = "refs/heads/{Branch}"
  }

  tags = {
    qaas = "true"
  }
}

resource "github_repository_webhook" "qaas" {
  repository = var.github_repo.name
  events     = ["push"]

  configuration {
    url          = aws_codepipeline_webhook.qaas.url
    content_type = "json"
    insecure_ssl = true
    secret       = var.webhook_secret
  }
}
