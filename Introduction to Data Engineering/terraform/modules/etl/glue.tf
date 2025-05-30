resource "aws_glue_catalog_database" "ml_database" {
  name        = "${var.project}-ml-db"
  description = "Database for performing ml from OLTP data"
}

resource "aws_glue_connection" "rds_connection" {
  name = "${var.project}-rds-connection"

  connection_properties = {
    JDBC_CONNECTION_URL = "jdbc:mysql://${var.host}:${var.port}/${var.database}"
    USERNAME            = var.username
    PASSWORD            = var.password
  }

  physical_connection_requirements {
    availability_zone      = data.aws_subnet.public_a.availability_zone
    security_group_id_list = [data.aws_security_group.db_sg.id]
    subnet_id              = data.aws_subnet.public_a.id
  }
}

resource "aws_glue_crawler" "s3_crawler" {
  name          = "${var.project}-ml-db-crawler"
  database_name = aws_glue_catalog_database.ml_database.name
  role          = aws_iam_role.glue_role.arn

  s3_target {
    path = "s3://${var.data_lake_bucket}/gold"
  }

  recrawl_policy {
    recrawl_behavior = "CRAWL_NEW_FOLDERS_ONLY"
  }

  schema_change_policy {
    delete_behavior = "LOG"
    update_behavior = "LOG"
  }
}

resource "aws_glue_job" "etl_job" {
  name         = "${var.project}-etl-job"
  role_arn     = aws_iam_role.glue_role.arn
  glue_version = "4.0"
  connections  = [aws_glue_connection.rds_connection.name]
  command {
    name            = "glueetl"
    script_location = "s3://${var.scripts_bucket}/${var.scripts_key}"
    python_version  = 3
  }

  default_arguments = {
    "--enable-job-insights" = "true"
    "--job-language"        = "python"
    "--glue_connection"     = aws_glue_connection.rds_connection.name
    "--glue_database"       = aws_glue_catalog_database.ml_database.name
    "--target_path"         = "s3://${var.data_lake_bucket}"
  }

  timeout = 5

  number_of_workers = 2
  worker_type       = "G.1X"
}
