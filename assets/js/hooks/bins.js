const Bins = {
  mounted() {
    // Function to clean expired bins and return valid ones
    const cleanExpiredBins = () => {
      let bins = JSON.parse(localStorage.getItem("bins") || "[]");
      const now = new Date();
      bins = bins.filter((bin) => new Date(bin.expires_at) > now);
      localStorage.setItem("bins", JSON.stringify(bins));
      return bins;
    };

    this.handleEvent("store_bin", ({ bin }) => {
      let bins = JSON.parse(localStorage.getItem("bins") || "[]");
      bins.push(bin);
      localStorage.setItem("bins", JSON.stringify(bins));
    });

    // Clear expired bins before initial load
    let bins = cleanExpiredBins();
    this.pushEvent("load_bins", { bins });

    // Clean expired bins every minute
    setInterval(() => {
      bins = cleanExpiredBins();
      this.pushEvent("load_bins", { bins });
    }, 60000);
  },
};

export default Bins;
