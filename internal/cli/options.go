package cli

type Option struct {
	Value   string
	Label   string
	Summary string
}

var subcommandOptions = []Option{
	{Value: "run", Label: "run", Summary: "Start a practice scenario"},
	{Value: "reveal", Label: "reveal", Summary: "Print the answer for the active scenario"},
	{Value: "stop", Label: "stop", Summary: "Tear down all active scenario state"},
	{Value: "list", Label: "list", Summary: "List available resource scenarios"},
	{Value: "status", Label: "status", Summary: "Show active run and service process state"},
}

var resourceOptions = []Option{
	{Value: "random", Label: "random", Summary: "Pick one resource scenario at random and hide the resource type"},
	{Value: "cpu", Label: "cpu", Summary: "CPU pressure from busy threads or non-I/O D-state kernel waits"},
	{Value: "memory", Label: "memory", Summary: "Resident memory utilization, reclaim pressure, or memcg OOM kills"},
	{Value: "disk", Label: "disk", Summary: "Direct io_uring read/write pressure against a bounded local file"},
	{Value: "network", Label: "network", Summary: "Socket traffic or backpressure over veth/netns, falling back to loopback"},
}

var scenarioResources = []string{"cpu", "memory", "disk", "network"}

func SubcommandOptions() []Option {
	return cloneOptions(subcommandOptions)
}

func ResourceOptions() []Option {
	return cloneOptions(resourceOptions)
}

func ProfileOptions(resource string) []Option {
	switch resource {
	case "cpu":
		return []Option{
			{Value: "random", Label: "random", Summary: "Pick one CPU profile at random"},
			{Value: "utilization", Label: "utilization", Summary: "Busy CPUs without intentionally creating a runnable backlog"},
			{Value: "runq", Label: "runq", Summary: "Runnable run-queue pressure with more workers than CPUs"},
			{Value: "kernelwait", Label: "kernelwait", Summary: "CPU burners plus non-I/O uninterruptible kernel waits"},
		}
	case "memory":
		return []Option{
			{Value: "random", Label: "random", Summary: "Pick one memory profile at random"},
			{Value: "resident", Label: "resident", Summary: "Large resident set with little ongoing reclaim after settling"},
			{Value: "pressure", Label: "pressure", Summary: "Large resident set plus bounded anonymous mapping churn"},
			{Value: "oom", Label: "oom", Summary: "Persistent cgroup-local OOM kills from a restarted child"},
		}
	case "disk":
		return []Option{
			{Value: "random", Label: "random", Summary: "Pick one disk profile at random"},
			{Value: "utilization", Label: "utilization", Summary: "Continuous queue-depth-one direct random I/O"},
			{Value: "saturation", Label: "saturation", Summary: "Short high-depth I/O bursts that expose queueing"},
		}
	case "network":
		return []Option{
			{Value: "random", Label: "random", Summary: "Pick one network profile at random"},
			{Value: "utilization", Label: "utilization", Summary: "Steady high-throughput TCP to a draining sink"},
			{Value: "saturation", Label: "saturation", Summary: "Slow-reading sink creates socket backpressure"},
			{Value: "highload", Label: "highload", Summary: "Offered-load TCP/UDP behavior with combined signals"},
		}
	default:
		return []Option{{Value: "random", Label: "random", Summary: "Pick one profile at random"}}
	}
}

func ProfileEnvVar(resource string) string {
	switch resource {
	case "cpu":
		return "CPU_PROFILE"
	case "memory":
		return "MEM_PROFILE"
	case "disk":
		return "DISK_PROFILE"
	case "network":
		return "NETWORK_PROFILE"
	default:
		return ""
	}
}

func IsResource(value string) bool {
	for _, resource := range scenarioResources {
		if value == resource {
			return true
		}
	}
	return false
}

func IsResourceOrRandom(value string) bool {
	return value == "random" || IsResource(value)
}

func cloneOptions(in []Option) []Option {
	out := make([]Option, len(in))
	copy(out, in)
	return out
}
