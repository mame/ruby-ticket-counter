require "net/http"
require "json"
require "time"

def fetch(api)
  json = Net::HTTP.get(URI.parse("https://bugs.ruby-lang.org/#{ api }"))
  JSON.parse(json, symbolize_names: true)
end

def get_updated_issues(since, &blk)
  i = 0
  total = nil
  begin
    list = fetch("issues.json?project_id=1&status_id=*&offset=#{ i }&limit=100&updaed_on=%3E%3D#{since}")
    list[:issues].map(&blk)
    i += list[:limit]
  end while i < list[:total_count]
end

def get_issue(id)
  fetch("issues/#{ id }.json?include=journals")
end

issues = []
get_updated_issues("2000-01-01T00:00:00Z") do |issue|
  id = issue[:id]
  tracker_name = issue[:tracker][:name]
  status = issue[:status][:name]
  created_on = issue[:created_on]
  closed_on = issue[:closed_on]
  issues << [id, tracker_name, status, created_on, closed_on]
end

events = []
issues.each do |id, tracker_name, status, created_on, closed_on|
  open = %w(Open Assigned Feedback).include?(status)
  events << [tracker_name, created_on, +1]
  events << [tracker_name, closed_on, -1] if !open
end
events = events.sort_by {|_, time, _| time }

t = Time.parse(events.first[1])
date = Time.utc(t.year, t.month, t.day)

bug_data, feature_data = [], []
count = { "Bug" => 0, "Feature" => 0 }
events.each do |tracker, time, diff|
  t = Time.parse(time)
  while date < t
    d = date.to_i * 1000
    bug_data << [d, count["Bug"]]
    feature_data << [d, count["Feature"]]
    date += 60 * 60 * 36
    date = Time.utc(date.year, date.month, date.day)
  end
  count[tracker] += diff if count[tracker]
end

html = DATA.read
html = html.sub("BUG_DATA") { JSON.generate(bug_data) }
html = html.sub("FEATURE_DATA") { JSON.generate(feature_data) }

File.write("index.html.tmp", html)

__END__
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <script src="https://code.highcharts.com/highcharts.js"></script>
  <title>Ruby ticket count chart</title>
</head>
<body>
<h1>Ruby ticket count chart</title>
<p><a href="https://bugs.ruby-lang.org/">https://bugs.ruby-lang.org/</a></p>
<p><a href="https://github.com/mame/ruby-ticket-counter">https://github.com/mame/ruby-ticket-counter</a></p>
<div id="container"></div>
<script type="text/javascript">
document.body.onload = function() {
  var options = {
    chart: { renderTo : "container", type: "area", zoomType: "x" },
    title: { text: "bugs.ruby-lang.org ticket counts" },
    xAxis: { type: "datetime" },
    yAxis: { title: { text: "Ticket count" } },
    series: [{ name: "feature", data: FEATURE_DATA }, { name: "bug", data: BUG_DATA }],
    plotOptions: {
      area: {
        stacking: "normal",
      }
    },
  };
  new Highcharts.Chart(options);
};
</script>
</body>
</html>
