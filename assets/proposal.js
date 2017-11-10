// Display some allocation example
//------------------------------------------------------------
// Allocations
//------------------------------------------------------------
function simpleAllocation(div) {
  // Get width from context
  var width = parseInt(div.style("width").replace("px", ""));
  var chartWidth = 0.5*width-margin.left-margin.right;
  var chartHeight = height-margin.bottom-margin.top;
  var controlWidth = 0.5*width;
  // The model
  var model = new Proxy({
    bid: 10,
    paid: 6,
    active: true,
    controller: (model) => null
  }, {
    set: (model, property, value, receiver) => {
      model[property] = value;
      model.controller(model);
    }
  });
  // Chart
  var chart = div.append("div").style("float","left").style("width",`${chartWidth+margin.left+margin.right}px`);
  var svg = chart.append("svg").attr("width", chartWidth+margin.left+margin.right)
    .attr("height", chartHeight+margin.bottom+margin.top);
  var g = svg.append("g")
    .attr("transform", `translate(${margin.left},${margin.top})`);
  var timeScale = d3.scaleLinear().domain([0,1]).range([0, chartWidth]);
  var bidScale = d3.scaleLinear().domain([0,1.1*model.bid]).range([chartHeight, 0]);
  // Add bid
  g.append("rect").attr("class", "bid").attr("x", chartWidth/4).attr("y", bidScale(model.bid))
    .attr("width", chartWidth/2).attr("height", bidScale(0)-bidScale(model.bid));
  g.append("rect").attr("class", "paid").attr("x", chartWidth/4).attr("y", bidScale(model.paid))
    .attr("width", chartWidth/2).attr("height", bidScale(0)-bidScale(model.paid));
  g.append("text").attr("class", "bid").attr("x",chartWidth/2).attr("y",bidScale(model.bid)+(bidScale(model.paid)-bidScale(model.bid))/2)
    .attr("text-anchor", "middle").style("font-size", `${fontSize}px`);
  g.append("text").attr("class", "paid").attr("x",chartWidth/2).attr("y",bidScale(model.paid)+(bidScale(0)-bidScale(model.paid))/2)
    .attr("text-anchor", "middle").style("font-size", `${fontSize}px`)
  // Add axis
  g.append("g").attr("transform", `translate(0,${chartHeight})`).call(d3.axisBottom(timeScale).ticks(1));
  g.append("g").attr("transform", `translate(0,0)`).call(d3.axisLeft(bidScale).ticks(numberTicks));
  // Control
  var f = d3.format(".1f");
  var control = div.append("div").attr("id", "direct-allocated")
    .style("float","left")
    .style("width",`${controlWidth-2*padding}px`)
    .style("height", `${height-2*padding}px`)
    .style("padding", `${padding}px`)
    .style("text-align", "left");
  control.append("div").text("Impression allocated to").style("padding", `${padding}px`).style("font-size", `${fontSize}px`);
  var allocatedDiv = control.append("div").text("not allocated").style("padding", `${padding}px`).style("font-size", `${2*fontSize}px`);
  control.append("div").style("padding", `${padding}px`).append("input").attr("type","checkbox").attr("id",name).attr("value","active")
    .style("zoom", "2").style("margin", 0)
    .on("change",(d,i,nodes) => {
      nodes[0].checked ? model.active = false : model.active = true;
    });
  control.append("div").text("Opportunity cost of direct").style("padding", `${padding}px`).style("font-size", `${fontSize}px`);
  var costdDiv = control.append("div").text("no cost").style("padding", `${padding}px`).style("font-size", `${2*fontSize}px`);
  // The controller
  model.controller = (model) => {
    if (model.active) {
      color = orange;
      var text = g.selectAll("text.bid")
      text.selectAll("tspan").remove();
      text.append("tspan").attr("x",chartWidth/2).attr("dy",-7).text("winning")
        .append("tspan").attr("x",chartWidth/2).attr("dy",15).text("bid");
      text = g.selectAll("text.paid")
      text.selectAll("tspan").remove();
      text.append("tspan").attr("x",chartWidth/2).attr("dy",-7).text(`$${f(model.paid)} CPM`)
        .append("tspan").attr("x",chartWidth/2).attr("dy",15).text("paid");
      allocatedDiv.text("RTB");
      costdDiv.text("no direct");
    } else {
      color = gray;
      var text = g.selectAll("text.bid")
      text.selectAll("tspan").remove();
      text.append("tspan").attr("x",chartWidth/2).attr("dy",-15).text("bid")
        .append("tspan").attr("x",chartWidth/2).attr("dy",15).text("overriden")
        .append("tspan").attr("x",chartWidth/2).attr("dy",15).text("by direct");
      text = g.selectAll("text.paid")
      text.selectAll("tspan").remove();
      text.append("tspan").attr("x",chartWidth/2).attr("dy",-15).text("no")
        .append("tspan").attr("x",chartWidth/2).attr("dy",15).text("RTB")
        .append("tspan").attr("x",chartWidth/2).attr("dy",15).text("revenue");
      allocatedDiv.text("Direct");
      costdDiv.text(`$${f(model.paid)} CPM`);
    }
    g.selectAll("rect.bid").style("fill", color.brighter());
    g.selectAll("rect.paid").style("fill", color);
    g.selectAll("text.bid").style("fill", color.darker());
    g.selectAll("text.paid").style("fill", color.darker().darker());
  };
  return div;
}

function priceBasedAllocation(div) {
  // Get width from context
  var width = parseInt(div.style("width").replace("px", ""));
  var chartWidth = 0.5*width-margin.left-margin.right;
  var chartHeight = height-margin.bottom-margin.top;
  var controlWidth = 0.5*width;
  // The model
  var model = new Proxy({
    bid: 10,
    direct: 6,
    paid: 6,
    secondBid: 6,
    active: true,
    controller: (model) => null
  }, {
    set: (model, property, value, receiver) => {
      model[property] = value;
      model.direct = Math.min(Math.max(0, model.direct), 1.1*model.bid);
      model.active = model.bid > model.direct;
      model.paid = model.active ? Math.max(model.direct, model.secondBid) : model.secondBid;
      model.controller(model);
    }
  });
  // Chart
  var chart = div.append("div").style("float","left").style("width",`${chartWidth+margin.left+margin.right}px`);
  var svg = chart.append("svg").attr("width", chartWidth+margin.left+margin.right)
    .attr("height", chartHeight+margin.bottom+margin.top);
  var g = svg.append("g")
    .attr("transform", `translate(${margin.left},${margin.top})`);
  var timeScale = d3.scaleLinear().domain([0,1]).range([0, chartWidth]);
  var bidScale = d3.scaleLinear().domain([0,1.1*model.bid]).range([chartHeight, 0]);
  // Add bid
  g.append("rect").attr("class", "bid").attr("x", chartWidth/4).attr("y", bidScale(model.bid))
    .attr("width", chartWidth/2).attr("height", bidScale(0)-bidScale(model.bid));
  g.append("rect").attr("class", "paid").attr("x", chartWidth/4).attr("y", bidScale(model.paid))
    .attr("width", chartWidth/2).attr("height", bidScale(0)-bidScale(model.paid));
  g.append("text").attr("class", "bid").attr("x",chartWidth/2).attr("y",bidScale(model.bid)+(bidScale(model.paid)-bidScale(model.bid))/2)
    .attr("text-anchor", "middle").style("font-size", `${fontSize}px`);
  g.append("text").attr("class", "paid").attr("x",chartWidth/2).attr("y",bidScale(model.paid)+(bidScale(0)-bidScale(model.paid))/2)
    .attr("text-anchor", "middle").style("font-size", `${fontSize}px`)
  // Add axis
  g.append("g").attr("transform", `translate(0,${chartHeight})`).call(d3.axisBottom(timeScale).ticks(1));
  g.append("g").attr("transform", `translate(0,0)`).call(d3.axisLeft(bidScale).ticks(numberTicks));
  g.append("line").attr("id", "direct")
    .attr("x1", -margin.left).attr("x2", chartWidth+margin.right)
    .style("stroke", gray).style("stroke-width", 1);
  // Add interaction
  svg.on("mousemove", () => model.direct = bidScale.invert(d3.mouse(g.node())[1]));
  // Control
  var f = d3.format(".1f");
  var control = div.append("div").attr("id", "direct-allocated")
    .style("float","left")
    .style("width",`${controlWidth-2*padding}px`)
    .style("height", `${height-2*padding}px`)
    .style("padding", `${padding}px`)
    .style("text-align", "left");
  control.append("div").text("Impression allocated to").style("padding", `${padding}px`).style("font-size", `${fontSize}px`);
  var allocatedDiv = control.append("div").text("not allocated").style("padding", `${padding}px`).style("font-size", `${2*fontSize}px`);
  control.append("div").text("Opportunity cost of direct").style("padding", `${padding}px`).style("font-size", `${fontSize}px`);
  var costdDiv = control.append("div").text("no cost").style("padding", `${padding}px`).style("font-size", `${2*fontSize}px`);
  control.append("div").text("Bid density gain").style("padding", `${padding}px`).style("font-size", `${fontSize}px`);
  var bidDensityDiv = control.append("div").text(`$${0} CPM`).style("padding", `${padding}px`).style("font-size", `${2*fontSize}px`);
  // The controller
  model.controller = (model) => {
    // Display direct bid
    g.select("#direct").attr("y1", bidScale(model.direct)).attr("y2", bidScale(model.direct))
    if (model.active) {
      color = orange;
      var text = g.selectAll("text.bid")
      text.selectAll("tspan").remove();
      if (bidScale(model.paid)-bidScale(model.bid)>30) {
        text.append("tspan").attr("x",chartWidth/2).attr("dy",-7).text("winning")
          .append("tspan").attr("x",chartWidth/2).attr("dy",15).text("bid");
      }
      text = g.selectAll("text.paid")
      text.selectAll("tspan").remove();
      text.append("tspan").attr("x",chartWidth/2).attr("dy",-7).text(`$${f(model.paid)} CPM`)
        .append("tspan").attr("x",chartWidth/2).attr("dy",15).text("paid");
      allocatedDiv.text("RTB");
      costdDiv.text("no direct");
      bidDensityDiv.text(`$${f(model.paid-model.secondBid)} CPM`);
    } else {
      color = gray;
      var text = g.selectAll("text.bid")
      text.selectAll("tspan").remove();
      text.append("tspan").attr("x",chartWidth/2).attr("dy",-15).text("bid")
        .append("tspan").attr("x",chartWidth/2).attr("dy",15).text("overriden")
        .append("tspan").attr("x",chartWidth/2).attr("dy",15).text("by direct");
      text = g.selectAll("text.paid")
      text.selectAll("tspan").remove();
      text.append("tspan").attr("x",chartWidth/2).attr("dy",-15).text("no")
        .append("tspan").attr("x",chartWidth/2).attr("dy",15).text("RTB")
        .append("tspan").attr("x",chartWidth/2).attr("dy",15).text("revenue");
      allocatedDiv.text("Direct");
      costdDiv.text(`$${f(model.paid)} CPM`);
      bidDensityDiv.text(`$${0} CPM`);
    }
    g.selectAll("rect.bid").style("fill", color.brighter());
    g.selectAll("rect.paid").attr("y", bidScale(model.paid)).attr("height", bidScale(0)-bidScale(model.paid)).style("fill", color);
    g.selectAll("text.bid").attr("y",bidScale(model.bid)+(bidScale(model.paid)-bidScale(model.bid))/2).style("fill", color.darker());
    g.selectAll("text.paid").attr("y",bidScale(model.paid)+(bidScale(0)-bidScale(model.paid))/2).attr("height", bidScale(0)-bidScale(model.paid)).style("fill", color.darker().darker());
  };
  return div;
}
// Show indicator
function showIndicator(selection, name, value, cls="indicator") {
  var div = selection.append("div").attr("class", cls)
    .style("display", "inline-block")
    .style("width", "100px")
    .style("padding", `${padding}px`)
    .style("text-align", "right");
  div.append("div").text(name).attr("class", "name").style("padding", `${padding}px`).style("font-size", `${fontSize}px`);;
  div.append("div").text(value).attr("class", "value").style("padding", `${padding}px`).style("font-size", `${2*fontSize}px`);
}

// Display bars
function barPlot(selection, cls, x, y) {
  selection.append("rect")
  .classed(cls, true)
  .attr("x", (d,i) => x(i))
  .attr("y", function(d,i) { return y(d); })
  .attr("width", x(0.4))
  .attr("height", function(d,i) { return y(0)-y(d); });
}

// RTB revenue
function cumulativeValue(bids, paids, value, cap=v=>v) {
  return d3.zip(bids,paids).reduce((result, bidPaid, index) => {
    if (result.length>0) {
      result.push([index, cap(last(result)[1]+value(bidPaid[0], bidPaid[1], index))]);
    } else {
      result.push([index, cap(value(bidPaid[0], bidPaid[1], index))]);
    }
    return result;
  }, []);
}

// Get last
function last(values) {
  return values[values.length-1];
}

//------------------------------------------------------------
// Priority allocation
//------------------------------------------------------------
function priority(div) {
  var chartWidth = width-margin.left-margin.right;
  var chartHeight = height-margin.bottom-margin.top;
  // The model
  var model = new Proxy({
    volume: auctionData.bids.length/2,
    rtbRevenue: [[0,0]],
    directCpm: 2,
    directVolume: 100,
    directRevenue: [[0,0]],
    controller: (model) => null
  }, {
    set: (model, property, value, receiver) => {
      model[property] = value;
      model.volume = Math.min(auctionData.bids.length, Math.max(0, model.volume));
      model.rtbRevenue = cumulativeValue(auctionData.bids, auctionData.paids, (b,p,i)=>i>model.volume ? p : 0);
      var volume = Math.min(model.directVolume, model.volume);
      model.directRevenue = [[0,0], [volume, volume*model.directCpm], [auctionData.bids.length, volume*model.directCpm]];
      model.controller(model);
    }
  });
  // The view
  var svg = div.append("svg").attr("width", width).attr("height", height);
  var g = svg.append("g").attr("transform", `translate(${margin.left},${margin.top})`);
  var impressionScale = d3.scaleLinear().domain([0, auctionData.bids.length]).range([0, chartWidth]),
    bidScale = d3.scaleLinear().domain([0, 0.9*d3.max(auctionData.paids)]).range([chartHeight, 0]),
    revenueScale = d3.scaleLinear().domain([0, 1.1*d3.sum(auctionData.paids)]).range([chartHeight, 0]);
  // Display active bids
  g.selectAll(".bid").data(auctionData.bids).enter()
    .call(barPlot, "bid active", impressionScale, bidScale);
  // and paids
  g.selectAll(".paid").data(auctionData.paids).enter()
    .call(barPlot, "paid active", impressionScale, bidScale);
  // Style bids
  g.selectAll(".bid").style("fill", gray.brighter());
  g.selectAll(".paid").style("fill", gray);
  // Add RTB revenue
  g.append("path").attr("id", "rtb-revenue")
    .style("stroke", orange).style("stroke-width", 3).style("fill", "none");
  // Add direct revenue
  g.append("path").attr("id", "direct-revenue")
    .style("stroke", blue).style("stroke-width", 3).style("fill", "none");
  // Add direct volume
  g.append("line").attr("id", "volume")
    .attr("y1", -margin.top).attr("y2", chartHeight+margin.bottom)
    .style("stroke", gray).style("stroke-width", 1);
  // Add axis
  g.append("g").attr("transform", `translate(0,${chartHeight})`).call(d3.axisBottom(impressionScale).ticks(numberTicks));
  g.append("g").attr("transform", `translate(0,0)`).call(d3.axisLeft(bidScale).ticks(numberTicks));
  g.append("g").attr("transform", `translate(${chartWidth},0)`).call(d3.axisRight(revenueScale).ticks(numberTicks));
  // Add direct volume marker
  g.append("g").attr("id", "direct-volume-marker").append("text")
    .attr("x", labelOffset).attr("text-anchor", "start")
    .style("font-size", `${fontSize}px`).style("fill", gray);
  // Add direct marker
  var directRevenueMarker = g.append("g").attr("id", "direct-revenue-marker")
    .attr("transform", `translate(${chartWidth}, ${revenueScale(last(model.directRevenue)[1])})`);
  directRevenueMarker.append("path").datum(model.directRevenue)
    .attr("d", d3.symbol().type(d3.symbolCircle))
    .style("fill", blue);
  directRevenueMarker.append("text")
      .attr("x", -labelOffset).attr("y", -labelOffset).attr("text-anchor", "end")
      .style("font-size", `${fontSize}px`).style("fill", blue);
  // Add RTB marker
  var rtbRevenueMarker = g.append("g")
    .attr("id", "rtb-revenue-marker");
  rtbRevenueMarker.append("path").datum(model.rtbRevenue)
    .attr("d", d3.symbol().type(d3.symbolCircle))
    .style("fill", orange);
  rtbRevenueMarker.append("text")
      .attr("x", -labelOffset).attr("y", -labelOffset).attr("text-anchor", "end")
      .style("font-size", `${fontSize}px`).style("fill", orange);
  // Add interaction
  svg.on("mousemove", () => model.volume = impressionScale.invert(d3.mouse(g.node())[0]));
  // Add comments
  div.append("div")
    .call(showIndicator, "Direct revenue", d3.format("$d")(model.directRevenue[model.directRevenue.length-1][1]), "direct")
    .call(showIndicator, "RTB revenue", d3.format("$d")(model.rtbRevenue[model.rtbRevenue.length-1][1]), "rtb")
    .call(showIndicator, "Total revenue", d3.format("$d")(model.directRevenue[model.directRevenue.length-1][1]+model.rtbRevenue[model.rtbRevenue.length-1][1]), "total");
  div.select(".total .name").style("font-weight", "bold")
  div.select(".total .value").style("font-weight", "bold")
  // The controller
  model.controller = (model) => {
    g.selectAll(".bid").classed("active", (d,i) => i>model.volume).style("fill", gray.brighter());
    g.selectAll(".paid").classed("active", (d,i) => i>model.volume).style("fill", gray);
    g.selectAll(".bid.active").style("fill", orange.brighter());
    g.selectAll(".paid.active").style("fill", orange);
    g.select("#direct-revenue").datum(model.directRevenue)
      .attr("d", d3.line().x(d => impressionScale(d[0])).y(d => revenueScale(d[1])));
    g.select("#rtb-revenue").datum(model.rtbRevenue)
      .attr("d", d3.line().x(d => impressionScale(d[0])).y(d => revenueScale(d[1])));
    g.select("#direct-volume-marker")
      .attr("transform", `translate(${impressionScale(model.volume)}, 0)`)
      .select("text").text(() => {
        if (model.volume < model.directVolume-padding) {
          return "The campaign is under-delivering"
        } else if (model.volume < model.directVolume+padding) {
          return "The campaign delivering the right amount"
        } else {
          return "The campaign is over-delivering"
        }
      });
    g.select("#direct-revenue-marker")
      .attr("transform", `translate(${chartWidth}, ${revenueScale(last(model.directRevenue)[1])})`)
      .select("text").text(`Direct revenue = ${d3.format("$d")(last(model.directRevenue)[1])}`);
    g.select("#rtb-revenue-marker")
      .attr("transform", `translate(${chartWidth}, ${revenueScale(last(model.rtbRevenue)[1])})`)
      .select("text").text(`RTB revenue = ${d3.format("$d")(last(model.rtbRevenue)[1])}`);
    g.select("line")
      .attr("x1", impressionScale(model.volume)).attr("x2", impressionScale(model.volume));
    div.select(".direct .value").text(d3.format("$d")(last(model.directRevenue)[1]));
    div.select(".rtb .value").text(d3.format("$d")(last(model.rtbRevenue)[1]));
    div.select(".total .value").text(d3.format("$d")(last(model.directRevenue)[1]+last(model.rtbRevenue)[1]));
  };
  return div;
}

//------------------------------------------------------------
// Competitive allocation
//------------------------------------------------------------
function competitive(div) {
  var chartWidth = width-margin.left-margin.right;
  var chartHeight = height-margin.bottom-margin.top;
  // The model
  var model = new Proxy({
    bid: 0,
    rtbRevenue: [[0,0]],
    directCpm: 2,
    directVolume: 100,
    directRevenue: [[0,0]],
    controller: (model) => null
  }, {
    set: (model, property, value, receiver) => {
      model[property] = value;
      model.bid = Math.max(0, model.bid);
      model.rtbRevenue = cumulativeValue(auctionData.bids, auctionData.paids, (b,p,i)=>model.bid<b ? p : 0);
      model.directRevenue = cumulativeValue(auctionData.bids, auctionData.paids, (b,p,i)=>model.bid>=b ? model.directCpm : 0, v=>Math.min(model.directVolume*model.directCpm,v));
      model.controller(model);
    }
  });
  // The view
  var svg = div.append("svg").attr("width", width).attr("height", height);
  var g = svg.append("g").attr("transform", `translate(${margin.left},${margin.top})`);
  var impressionScale = d3.scaleLinear().domain([0, auctionData.bids.length]).range([0, chartWidth]),
    bidScale = d3.scaleLinear().domain([0, 0.9*d3.max(auctionData.paids)]).range([chartHeight, 0]),
    revenueScale = d3.scaleLinear().domain([0, 1.1*d3.sum(auctionData.paids)]).range([chartHeight, 0]);
  // Display active bids
  g.selectAll(".bid").data(auctionData.bids).enter()
    .call(barPlot, "bid active", impressionScale, bidScale);
  // and paids
  g.selectAll(".paid").data(auctionData.paids).enter()
    .call(barPlot, "paid active", impressionScale, bidScale);
  // Style bids
  g.selectAll(".bid").style("fill", gray.brighter());
  g.selectAll(".paid").style("fill", gray);
  // Add RTB revenue
  g.append("path").attr("id", "rtb-revenue")
    .style("stroke", orange).style("stroke-width", 3).style("fill", "none");
  // Add direct revenue
  g.append("path").attr("id", "direct-revenue")
    .style("stroke", blue).style("stroke-width", 3).style("fill", "none");
  // Add direct volume
  g.append("line").attr("id", "volume")
    .attr("x1", -margin.left).attr("x2", chartWidth+margin.right)
    .style("stroke", gray).style("stroke-width", 1)
  // Add axis
  g.append("g").attr("transform", `translate(0,${chartHeight})`).call(d3.axisBottom(impressionScale).ticks(numberTicks));
  g.append("g").attr("transform", `translate(0,0)`).call(d3.axisLeft(bidScale).ticks(numberTicks));
  g.append("g").attr("transform", `translate(${chartWidth},0)`).call(d3.axisRight(revenueScale).ticks(numberTicks));
  // Add direct bid marker
  g.append("g").attr("id", "direct-bid-marker").append("text")
    .attr("x", labelOffset).attr("y", -labelOffset).attr("text-anchor", "start")
    .style("font-size", `${fontSize}px`).style("fill", gray);
  // Add direct marker
  var directRevenueMarker = g.append("g").attr("id", "direct-revenue-marker")
    .attr("transform", `translate(${chartWidth}, ${revenueScale(last(model.directRevenue)[1])})`);
  directRevenueMarker.append("path").datum(model.directRevenue)
    .attr("d", d3.symbol().type(d3.symbolCircle))
    .style("fill", blue);
  directRevenueMarker.append("text")
      .attr("x", -labelOffset).attr("y", -labelOffset).attr("text-anchor", "end")
      .style("font-size", `${fontSize}px`).style("fill", blue);
  // Add RTB marker
  var rtbRevenueMarker = g.append("g")
    .attr("id", "rtb-revenue-marker");
  rtbRevenueMarker.append("path").datum(model.rtbRevenue)
    .attr("d", d3.symbol().type(d3.symbolCircle))
    .style("fill", orange);
  rtbRevenueMarker.append("text")
      .attr("x", -labelOffset).attr("y", -labelOffset).attr("text-anchor", "end")
      .style("font-size", `${fontSize}px`).style("fill", orange);
  // Add interaction
  svg.on("mousemove", () => model.bid = bidScale.invert(d3.mouse(g.node())[1]));
  // Add comments
  div.append("div")
    .call(showIndicator, "Direct revenue", d3.format("$d")(model.directRevenue[model.directRevenue.length-1][1]), "direct")
    .call(showIndicator, "RTB revenue", d3.format("$d")(model.rtbRevenue[model.rtbRevenue.length-1][1]), "rtb")
    .call(showIndicator, "Total revenue", d3.format("$d")(model.directRevenue[model.directRevenue.length-1][1]+model.rtbRevenue[model.rtbRevenue.length-1][1]), "total");
  div.select(".total .name").style("font-weight", "bold")
  div.select(".total .value").style("font-weight", "bold")
  // The controller
  model.controller = (model) => {
    g.selectAll(".bid").classed("active", (d,i) => model.bid<auctionData.bids[i]).style("fill", gray.brighter());
    g.selectAll(".paid").classed("active", (d,i) => model.bid<auctionData.bids[i]).style("fill", gray);
    g.selectAll(".bid.active").style("fill", orange.brighter());
    g.selectAll(".paid.active").style("fill", orange);
    g.select("#direct-revenue").datum(model.directRevenue)
      .attr("d", d3.line().x(d => impressionScale(d[0])).y(d => revenueScale(d[1])));
    g.select("#rtb-revenue").datum(model.rtbRevenue)
      .attr("d", d3.line().x(d => impressionScale(d[0])).y(d => revenueScale(d[1])));
    g.select("#direct-bid-marker")
      .attr("transform", `translate(0, ${bidScale(model.bid)})`)
      .select("text").text(() => {
        if (last(model.directRevenue)[1]<model.directVolume*model.directCpm-padding) {
          return "The campaign is under-delivering"
        } else if (model.directRevenue[model.directRevenue.length-1-padding][1]<model.directVolume*model.directCpm) {
          return "The campaign is delivering the right amount"
        } else {
          return "The campaign is over-delivering"
        }
      });
    g.select("#direct-revenue-marker")
      .attr("transform", `translate(${chartWidth}, ${revenueScale(last(model.directRevenue)[1])})`)
      .select("text").text(`Direct revenue = ${d3.format("$d")(last(model.directRevenue)[1])}`);
    g.select("#rtb-revenue-marker")
      .attr("transform", `translate(${chartWidth}, ${revenueScale(last(model.rtbRevenue)[1])})`)
      .select("text").text(`RTB revenue = ${d3.format("$d")(last(model.rtbRevenue)[1])}`);
    g.select("line")
      .attr("y1", bidScale(model.bid)).attr("y2", bidScale(model.bid));
    div.select(".direct .value").text(d3.format("$d")(last(model.directRevenue)[1]));
    div.select(".rtb .value").text(d3.format("$d")(last(model.rtbRevenue)[1]));
    div.select(".total .value").text(d3.format("$d")(last(model.directRevenue)[1]+last(model.rtbRevenue)[1]));
  };
  return div;
}
// Show indicator
function slider(selection, name, value, interval, n, onchange, cls="slider") {
  var f = d3.format(".1f");
  var div = selection.append("div")
    .attr("id", name).attr("class", cls)
    .style("display", "inline-block")
    .style("width", `${0.1*width-2*padding}px`)
    .style("height", `${height-2*padding}px`)
    .style("padding", `${padding}px`)
    .style("text-align", "right");
  div.append("div").text(name).attr("class", "name").style("padding", `${padding}px`).style("font-size", `${fontSize}px`);
  var valueDiv = div.append("div").text(value).attr("class", "value").style("padding", `${padding}px`).style("font-size", `${2*fontSize}px`);
  div.append("input").attr("type","range").attr("id",name).attr("min",0).attr("max",n-1)
    .attr("step",1).attr("value",Math.round((n-1)*(value-interval[0])/(interval[1]-interval[0]))).style("-webkit-appearance","slider-vertical")
    .style("width", `${0.1*width-2*padding}px`)
    .style("height", `${0.6*height}px`)
    .style("padding", `${padding}px`).style("margin", 0)
    .on("input",(d,i,nodes) => {
      var value = interval[0] + nodes[0].value*(interval[1]-interval[0])/(n-1);
      valueDiv.text(f(value));
      onchange(value);
    });
}
// Display pde solutions
//------------------------------------------------------------
// PDE solution
//------------------------------------------------------------
function pde(div) {
  var chartWidth = 0.7*width-margin.left-margin.right;
  var chartHeight = height-margin.bottom-margin.top;
  var controlWidth = 0.3*width;
  // The model
  var model = new Proxy({
    nTime: 50,
    timeInterval: [0,1],
    sigma: 1,
    sigmaIndex: Math.round((20-1)*(1-0)/(10-0)),
    sigmaInterval: [0,10],
    nSigma: 20,
    shock: 1,
    shockIndex: Math.round((5-1)*(1-0.1)/(1-0.1)),
    shockInterval: [0.1,1],
    nShock: 5,
    a: [],
    aInterval: [0,10],
    goal0: 1,
    goalT: [],
    goalIndex: Math.round((10-1)*(1-0.5)/(2-0.5)),
    goalInterval: [0.5,2],
    nGoal: 10,
    controller: (model) => null
  }, {
    set: (model, property, value, receiver) => {
      model[property] = value;
      if (property==="sigma") model.sigmaIndex=Math.round((20-1)*(value-0)/(10-0));
      if (property==="shock") model.shockIndex=Math.round((5-1)*(value-0.1)/(1-0.1));
      if (property==="goal0") model.goalIndex=Math.round((10-1)*(value-0.5)/(2-0.5));
      model.a = pdeData.a[model.sigmaIndex][model.goalIndex][model.shockIndex];
      model.goalT = pdeData.g[model.sigmaIndex][model.goalIndex][model.shockIndex];
      model.controller(model);
    }
  });
  // Chart
  div.style("width",`${width}px`);
  var chart = div.append("div").style("float","left").style("width",`${chartWidth+margin.left+margin.right}px`);
  var svg = chart.append("svg").attr("width", chartWidth+margin.left+margin.right)
    .attr("height", chartHeight+margin.bottom+margin.top);
  var g = svg.append("g")
    .attr("transform", `translate(${margin.left},${margin.top})`);
  var timeScale = d3.scaleLinear().domain([0, 1]).range([0, chartWidth]),
    bidScale = d3.scaleLinear().domain(model.aInterval).range([chartHeight, 0]),
    goalScale = d3.scaleLinear().domain([0,2]).range([chartHeight, 0]);
  // Add RTB revenue
  g.append("path").attr("id", "bid-strategy")
    .style("stroke", orange).style("stroke-width", 3).style("fill", "none");
  g.append("path").attr("id", "goal")
    .style("stroke", blue).style("stroke-width", 3).style("fill", "none");
  // Add axis
  g.append("g").attr("transform", `translate(0,${chartHeight})`).call(d3.axisBottom(timeScale).ticks(numberTicks));
  g.append("g").attr("transform", `translate(0,0)`).call(d3.axisLeft(bidScale).ticks(numberTicks));
  g.append("g").attr("transform", `translate(${chartWidth},0)`).call(d3.axisRight(goalScale).ticks(numberTicks));
  // Control
  var control = div.append("div").style("float","left").style("width",`${controlWidth}px`)
    .call(slider, "Sigma", model.sigma, model.sigmaInterval, model.nSigma, (value) => {model.sigma = value;})
    .call(slider, "Goal", model.goal0, model.goalInterval, model.nGoal, (value) => {model.goal0 = value;})
    .call(slider, "Shock", model.shock, model.shockInterval, model.nShock, (value) => {model.shock = value;});
  // The controller
  model.controller = (model) => {
    g.select("#bid-strategy").datum(model.a)
      .attr("d", d3.line().x((d,i) => timeScale(i/model.nTime)).y(d => bidScale(d)));
    g.select("#goal").datum(model.goalT)
      .attr("d", d3.line().x((d,i) => timeScale(i/model.nTime)).y(d => goalScale(d)));
  };
  return div;
}
