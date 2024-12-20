moved {
  from = aws_kms_key.cijenkinsio-agents-2
  to   = aws_kms_key.cijenkinsio_agents_2
}
moved {
  from = module.cijenkinsio-agents-2
  to   = module.cijenkinsio_agents_2
}
moved {
  from = module.cijenkinsio-agents-2_admin_sa
  to   = module.cijenkinsio_agents_2_admin_sa
}
moved {
  from = helm_release.cluster-autoscaler
  to = helm_release.cluster_autoscaler
}
