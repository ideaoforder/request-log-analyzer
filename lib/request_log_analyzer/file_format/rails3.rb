module RequestLogAnalyzer::FileFormat
  # Lograge FileFormat class for Rails 3 logs.


# DEFAULT RAILS
# Started GET "/" for 127.0.0.1 at 2012-03-10 14:28:14 +0100
# Processing by HomeController#index as HTML
#   Rendered text template within layouts/application (0.0ms)
#   Rendered layouts/_assets.html.erb (2.0ms)
#   Rendered layouts/_top.html.erb (2.6ms)
#   Rendered layouts/_about.html.erb (0.3ms)
#   Rendered layouts/_google_analytics.html.erb (0.4ms)
# Completed 200 OK in 79ms (Views: 78.8ms | ActiveRecord: 0.0ms)

# LOGRAGE
# method=GET path=/items/203341/edit format=html controller=items action=edit status=200 duration=2205.17 view=1210.69 db=173.89 time=2015-02-02 13:33:08 -0500 params={"id"=>"203341"} host=localhost source=Whiplash


  class Rails3 < Base
    extend CommonRegularExpressions

    # beta4: Started GET "/" for 127.0.0.1 at Wed Jul 07 09:13:27 -0700 2010 (different time format)
    line_definition :log_line do |line|
      line.regexp = /method=([A-Z]+) path=(\S*) format=(\w+) controller=(\w+) action=(\w+) status=(\d+) duration=([0-9\.]*) view=([0-9\.]*) db=([0-9\.]*) time=(#{timestamp('%a %b %d %H:%M:%S %z %Y')}|#{timestamp('%Y-%m-%d %H:%M:%S %z')}) params=(\{.*\}) host=(\S*) source=(\S*)/

      line.capture(:method)
      line.capture(:path)
      line.capture(:format)
      line.capture(:controller)
      line.capture(:action)

      line.capture(:status).as(:integer)
      line.capture(:duration).as(:duration, unit: :msec)
      line.capture(:view).as(:duration, unit: :msec)
      line.capture(:db).as(:duration, unit: :msec)

      line.capture(:timestamp).as(:timestamp)
      line.capture(:params).as(:eval)

      line.capture(:host)
      line.capture(:source)
    end

    # ActionController::RoutingError (No route matches [GET] "/missing_stuff"):
    line_definition :routing_errors do |line|
      line.teaser = /RoutingError/
      line.regexp = /No route matches \[([A-Z]+)\] "([^"]+)"/
      line.capture(:missing_resource_method).as(:string)
      line.capture(:missing_resource).as(:string)
    end

    # ActionView::Template::Error (undefined local variable or method `field' for #<Class>) on line #3 of /Users/willem/Code/warehouse/app/views/queries/execute.csv.erb:
    line_definition :failure do |line|
      line.footer = true
      line.regexp = /((?:[A-Z]\w*[a-z]\w+\:\:)*[A-Z]\w*[a-z]\w+) \((.*)\)(?: on line #(\d+) of (.+))?\:\s*$/

      line.capture(:error)
      line.capture(:message)
      line.capture(:line).as(:integer)
      line.capture(:file)
    end

    REQUEST_CATEGORIZER = lambda { |request| "#{request[:controller]}##{request[:action]}.#{request[:format]}" }

    report do |analyze|

      analyze.timespan
      analyze.hourly_spread

      analyze.frequency category: REQUEST_CATEGORIZER, title: 'Most requested'
      analyze.frequency :method, title: 'HTTP methods'
      analyze.frequency :status, title: 'HTTP statuses returned'

      analyze.duration :duration, category: REQUEST_CATEGORIZER, title: 'Request duration', line_type: :completed
      analyze.duration :partial_duration, category: :rendered_file, title: 'Partials rendering time', line_type: :rendered
      analyze.duration :view, category: REQUEST_CATEGORIZER, title: 'View rendering time', line_type: :completed
      analyze.duration :db, category: REQUEST_CATEGORIZER, title: 'Database time', line_type: :completed

      analyze.frequency category: REQUEST_CATEGORIZER, title: 'Process blockers (> 1 sec duration)',
        if: lambda { |request| request[:duration] && request[:duration] > 1.0 }

      analyze.frequency category: lambda { |x| "[#{x[:missing_resource_method]}] #{x[:missing_resource]}" },
        title: 'Routing Errors', if: lambda { |request| !request[:missing_resource].nil? }
    end

    class Request < RequestLogAnalyzer::Request
      # Used to handle conversion of abbrev. month name to a digit
      MONTHS = %w(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec)

      def convert_timestamp(value, _definition)
        # the time value can be in 2 formats:
        # - 2010-10-26 02:27:15 +0000 (ruby 1.9.2)
        # - Thu Oct 25 16:15:18 -0800 2010
        if value =~ /^#{CommonRegularExpressions::TIMESTAMP_PARTS['Y']}/
          value.gsub!(/\W/, '')
          value[0..13].to_i
        else
          value.gsub!(/\W/, '')
          time_as_str = value[-4..-1] # year
          # convert the month to a 2-digit representation
          month = MONTHS.index(value[3..5]) + 1
          month < 10 ? time_as_str << "0#{month}" : time_as_str << month.to_s

          time_as_str << value[6..13] # day of month + time
          time_as_str.to_i
        end
      end


      def sanitize_parameters(parameter_string)
        parameter_string.force_encoding("UTF-8")
          .gsub(/#</, '"')
          .gsub(/>, \"/, '", "')
          .gsub(/>>}/, '\""}') # #< ... >>}
          .gsub(/>>, \"/, '\"", "') # #< ... >>, "
          .gsub(/", @/, '\", @') # #< ... @content_type="image/jpeg", @ ... >>
          .gsub(/="/, '=\"') # #< ... filename="IMG_2228.JPG" Content-Type: image/jpeg", ... >>
          .gsub(/=\\", "/, '=", "') # redo "...hSMjag0w=\\",
          .gsub(/=\\"}/, '="}') # redo "...hSMjag0w=\\"}
          .gsub(/\\0/, '')
      end
    end
  end
end