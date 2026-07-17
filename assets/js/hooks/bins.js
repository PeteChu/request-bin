const Bins = {
  mounted() {
    const readBins = () => {
      try {
        return JSON.parse(localStorage.getItem("bins") || "[]");
      } catch (_error) {
        localStorage.removeItem("bins");
        return [];
      }
    };

    const cleanExpiredBins = () => {
      const now = new Date();
      const bins = readBins().filter((bin) => new Date(bin.expires_at) > now);
      localStorage.setItem("bins", JSON.stringify(bins));
      return bins;
    };

    this.handleEvent("store_bin", ({ bin }) => {
      const bins = readBins();
      bins.push(bin);
      localStorage.setItem("bins", JSON.stringify(bins));
    });

    this.pushEvent("load_bins", { bins: cleanExpiredBins() });

    this.cleanInterval = setInterval(() => {
      this.pushEvent("load_bins", { bins: cleanExpiredBins() });
    }, 60000);
  },
  destroyed() {
    clearInterval(this.cleanInterval);
  },
};

export default Bins;
