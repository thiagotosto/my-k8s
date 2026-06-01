output "sa_email" {
  value       = google_service_account.cases_summarizer.email
  description = "GCP SA email for Workload Identity binding"
}
