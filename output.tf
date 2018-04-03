output "public" {
  value = "${aws_instance.public.public_ip}"
}

output "private" {
  value = "${aws_instance.private.private_ip}"
}