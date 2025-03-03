const Bins = {
  mounted() {
    this.handleEvent("store_bin", ({bin}) => {
      let bins = JSON.parse(localStorage.getItem("bins") || "[]")
      bins.push(bin)
      localStorage.setItem("bins", JSON.stringify(bins))
    })

    this.pushEvent("load_bins", {
      bins: JSON.parse(localStorage.getItem("bins") || "[]")
    })

    // Clean expired bins every minute
    setInterval(() => {
      let bins = JSON.parse(localStorage.getItem("bins") || "[]")
      const now = new Date()
      bins = bins.filter(bin => new Date(bin.expires_at) > now)
      localStorage.setItem("bins", JSON.stringify(bins))
      this.pushEvent("load_bins", {bins})
    }, 60000)
  }
}

export default Bins;
