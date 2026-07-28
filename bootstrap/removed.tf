/*This project initially used a DynamoDB table for tf_lock, 
but this has been deprecated for the newer use_lockfile attribute
in the state bucket. I used a removed block here instead of terraform
state rm through the terminal. This is because the removed block lets
you preview the results of the operation, which makes it a safer way
to remove resources, as per HashiCorp documentation:
https://developer.hashicorp.com/terraform/language/state/remove.
*/

removed {
  from = aws_dynamodb_table.tf_lock

  lifecycle {
    destroy = false
  }
}
