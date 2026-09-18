.pragma library

// Plugin-internal rendezvous for visual entry points and the kept service.
// Omarchy may replace a scoped shell facade while retaining a keepLoaded menu;
// the service itself is refreshed by the host, so visual components resolve
// their own service here instead of retaining a revoked host capability.
var service = null

function publish(value) {
  service = value || null
}

function clear(value) {
  if (service === value) service = null
}

function current() {
  return service
}
