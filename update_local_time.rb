require 'open-uri'
require 'date'
require 'zip'
require 'json'

@downlaod_addrss_url = "https://timezonedb.com/files/timezonedb.csv.zip"
@coordinated_version_url = "https://timezonedb.com/date.txt"




# download latest currect date for update test
#
def get_coordinated_version
  begin
    open(@coordinated_version_url) {|f|
      f.each_line {|line| return line.sub("\n","").sub("\r","")}
    }
  rescue => e
    $stderr.puts "Error with version number #{e}"
    exit(1)
  end
end


# download and extract archive, process files
#
def download_archive 
  begin
    pfin = {}
    uzone = {}
    content = open(@downlaod_addrss_url)
    Zip::File.open_buffer(content) do |zip_file|
      # Handle entries one by one
      zip_file.each do |entry|
        if entry.name == "zone.csv" # first
          $stderr.puts "Extracting #{entry.name}"
          entry.get_input_stream.read.each_line do |l|
            x = l.delete('"').delete("\n").split(/,/)
            uzone[x[0]] = x[2]
            pfin[x[2]] = []
          end
        end
      end
      zip_file.each do |entry|
       if entry.name == "timezone.csv" # second
          $stderr.puts "Extracting #{entry.name}"
          entry.get_input_stream.read.each_line do |l|
            x = l.delete('"').delete("\n").split(/,/)
            pfin[uzone[x[0].to_s]] << {'change'=>x[2],"val"=>x[3],"st"=>x[4]}
          end
        end
      end
    end
  
    # make sure it is in chronological order 
    pfin.each do |k,v|
      pfin[k].sort_by { |v| v["change"] }
    end
    IO.write("out.json",pfin)
    return pfin
  rescue => e
    $stderr.puts "Error downloading archive #{e}"
    exit(1)
  end
end



# remove unwanted decades from search
#
def prune start, stop, pfin
  smallest = 999999999
  largest = -999999999
  fin = {}

  if not ARGV[0].nil? and not ARGV[1].nil?

    if ARGV[0].length == 4 # use year for maximum, example <2018>
      smallest =  (((ARGV[0].to_i) -1) * 3600 * 24 * 365) - (1970 * 3600 * 24 * 365)
    else # use epoch time in seconds
      smallest = ARGV[0].to_i
    end


    if ARGV[1].length == 4 # use year for maximum, example <2025>
      largest =  (((ARGV[1].to_i) +1) * 3600 * 24 * 365) - (1970 * 3600 * 24 * 365)
    else # use epoch time in seconds
      largest = ARGV[1].to_i
    end

  else # defaults to everything, quite large, typically pointless
    pfin.each do |k,v|
      v.each do |i|
        if i['change'].to_i < smallest
          smallest = i['change'].to_i
        end
        if i['change'].to_i > largest
          largest = i['change'].to_i
        end
      end
    end
  end

  # disquality out of range values
  pfin.each do |k,v|
    fin[k] = []
    v.each do |i|
      if  (i['change'].to_i) > smallest and (i['change'].to_i) < largest
        fin[k] << i
      end
    end
  end

  return fin

end


def local_version_exist
  File.file?("./local_time/COORDINATED_VERSION.txt")
end

def check_date date
  begin
    Date.parse(date)
    return true
  rescue => e
    return false
  end
end


def get_local_coordinated_version
  begin
    local = IO.read("./local_time/COORDINATED_VERSION.txt")
    $stderr.puts "retrieving local coordinating date #{local}"
    return local
  rescue => e
    $stderr.puts "Error opening current version #{e}"
  end
end

def do_update new_version
  if local_version_exist
    if new_version == get_local_coordinated_version
      return false
    else
      return true
    end
  else
    return true
  end
end

def write_coordinated_version new_version
  begin
    if check_date new_version
      IO.write("./local_time/COORDINATED_VERSION.txt", new_version)
    else
      $stderr.puts "something wrong with new date #{new_version}"
      exit(1)
    end
  rescue => e
    $stderr.puts "Error writng coordinated version #{e}"
    exit(1)
  end
end


apends = "
var geoTz = require('geo-tz')
function get_local_correction(time, geo_lon, geo_lat) { 
  var list = dict[geoTz(geo_lon, geo_lat)];
  var samp = 0;
  for (let i in list){
    if (parseInt(list[i][\"change\"]) >= time) {
      return (samp);
    }
    samp = parseInt(list[i][\"val\"]);
  } 

  return (0);
}
exports.get_local_correction = get_local_correction;
"


new_version = get_coordinated_version
if check_date new_version
  $stderr.puts "retrieved current timezone date #{new_version}"
  if do_update new_version
    res = download_archive 
    fin = prune(ARGV[0], ARGV[1], res)
    sfin = "var dict = #{JSON.generate(fin)} #{apends}"
    #IO.write("correct_tz.json", JSON.pretty_generate(fin))
    IO.write("./local_time/index.js", sfin)
    write_coordinated_version new_version
    $stderr.puts "update complete"
    exit(0)
  else
    $stderr.puts "Matches repo date, nothing to do"
  end
end

