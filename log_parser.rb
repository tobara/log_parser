# To parse a log file, please provide file name in command line e.g. `$ ruby log_parser.rb 2014-09-03.log`
require './heroku_codes.rb'

class LogParser

  def initialize(file_name)
    @file_name = file_name
    @not_found = Hash.new(0)
    @service_time = {service: 0, count: 0}
    @average_serve = 0
    @table_count = Hash.new(0)
    @error_codes = Hash.new(0)
  end

  def read_logs
    log_file = File.open(@file_name, "r")
    log_array = []
    log_file.each_line do |log|
      log.gsub!(/[["]]/, '')
      log_array << log
    end

    parse_facility(log_array)

    print_results

  end


  def parse_facility(log_array)
    facilities = [:Local3, :Local7, :Local5, :Syslog]
    local = log_array.group_by do |log|
      facilities.each { |f| break key = f if log.include?(f.to_s) }
    end
    parse_status(local[:Local3])

    count_tables(local[:Local7])

    status_error = local.values_at(:Local3, :Local7)
    parse_status_error(status_error)

    count_codes(local)

  end

  def parse_status(local_three)
    local_three.each do |log|
      case
      when log.include?("status=4")
        collect_urls(log)

      when log.include?("status=3")
        write_redirects(log)

        collect_serve_times(log)

      when log.include?("status=2")
        collect_serve_times(log)

      end
    end
  end

  def collect_urls(log)
    prefix = [/(?=(host=)(?<host>(\S+)))/, /(?=(path=)(?<path>(\S+)))/]
    url = log.match(prefix[0])[:host] + log.match(prefix[1])[:path]
    @not_found[url] += 1
  end

  def write_redirects(log)
    File.open("Redirects-"+@file_name, "a") { |f| f << log }
  end

  def collect_serve_times(log)
    service = log.scan(/service=(\d+)ms/)[0][0].to_i
    @service_time[:service] += service
    @service_time[:count] += 1
  end

  def count_tables(local_seven)
    char_exp = /FROM.(.\w+)/
    local_seven.select { |log| log.include?('FROM') } .each do |log|
      table_log = log.match(char_exp)[1].delete('\"')
      @table_count[table_log] += 1
    end
  end

  def parse_status_error(status_error)
    status_error.flatten.each do |log|
      write_error(log) if log.include?("status=5")
    end
  end

  def write_error(log)
    File.open("5xx_ServerError"+@file_name, "a") { |f| f << log}
  end

  def count_codes(log_codes)
    log_codes.values.flatten.each do |log|
      key = log.scan(/[HRL]\d{2}/).first
      @error_codes[key] += 1 if key != nil
    end
    @code_description = Array.new
    @error_codes.each_key { |k| @code_description << HerokuCodes::CODES[k] }
  end

  def print_results
    print_not_found
    print_serve_times
    print_table_counts
    print_redirection
    print_error_codes
  end

  def print_not_found
    puts %(\n\n A List of URLs that were not found (404 error), including the
    number of times each URL was requested.\n\n\n)

    puts %(\t\t\t|URL|\t\t\t\t\t\t|Number of Requests|\n\n)
    total_not_found = 0
    @not_found.each do |key, value|
      total_not_found += value
      puts %(\t#{key[0...60].ljust(60)}\t\t#{value})
    end
    puts %(\n\t-----------------------------------------------------------------
        TOTAL NUMBER OF REQUESTS ===> #{total_not_found}\n\n\n)
  end

  def print_serve_times
    average_service_time = @service_time[:service] /  @service_time[:count]
    puts %(Average time to serve a page.\n\n
        Average serve time per page is #{average_service_time} /ms based
        on #{@service_time[:count]} requests.\n\n\n)
  end

  def print_table_counts
    table, count = @table_count.max_by { |table, count| count }
    puts %(Which database table is most frequently loaded?\n\n
        The "#{table}" table was loaded [accessed] #{count} times.\n
        To view a list of all tables and the total number of times they
        were loaded, please view LoadedTables-#@file_name\n\n\n)
  end

  def print_redirection
    puts %(Is any URL redirection taking place?\n\n
        All URL redirects have been placed in Redirects-#@file_name\n\n\n)
  end

  def print_error_codes
    puts %(Are there any server errors?\n\n\n
        All HTTP codes that resulted in 5xx have been placed in:\n
        5xxCodes-#@file_name\n\n
        Also, the following Heroku Server Error Codes that were discovered
        are listed below.  Along with their corresponding descriptions, and the
        number of times each error occured.\n\n)
    n = 0
    @error_codes.each do |k,v|
      puts %(\t#{k} Error: #{"%02d" %v} Time(s) => #{@code_description[n]}\n\n)
      n += 1
    end
    puts %(Next log please.\n\n)
  end
end

@log_parser = LogParser.new(ARGV[0])
@log_parser.read_logs




