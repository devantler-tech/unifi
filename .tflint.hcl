# tflint configuration — HCL hygiene beyond `tofu validate`.
#
# The bundled `terraform` ruleset catches deprecated syntax, unused
# declarations, untyped variables, unpinned module sources and other smells
# that `tofu validate` (schema/syntax only) does not. There is no published
# tflint ruleset for the filipowm/unifi provider, so we rely on the terraform
# ruleset; revisit if one becomes available.
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}
