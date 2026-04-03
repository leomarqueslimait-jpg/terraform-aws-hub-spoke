# Route Tables — Inline Routes vs aws_route

My initial plan was to pass the default route via nat_gateway inside
`aws_route_table` as:

```hcl
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this[0].id
  }
}
```

And then add routes to the table later through the TGW module using:

```hcl
resource "aws_route" "hub_to_spoke" {
  route_table_id         = var.hub_private_route_table_id
  destination_cidr_block = "10.1.0.0/16"
  transit_gateway_id     = aws_ec2_transit_gateway.this.id
}
```

However, if you add a route block inside the resource `aws_route_table`
(inline route), Terraform will only take those values and ignore any routes
we want to inject using the `aws_route` resource.

Using inline routes is better for simple architectures where everything is
managed by one environment or module, since it is simpler and has less
resources and overhead.

Using no route blocks and adding routes via `aws_route` is the better way
to go in a more complex architecture with multiple modules and environments,
so you have more flexibility.
