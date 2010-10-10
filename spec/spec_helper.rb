require 'rubygems'
require 'ruby2ruby'

$LOAD_PATH.unshift(File.dirname(__FILE__))
$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
require 'sourcify'

# ///////////////////////////////////////////////////////////
# Regenerate ragel-based scanner
# ///////////////////////////////////////////////////////////

ragel_dir = File.join(File.dirname(__FILE__), '..', 'lib', 'sourcify', 'proc')
ragel_file = File.join(ragel_dir, 'scanner.rl')
ruby_file = File.join(ragel_dir, 'scanner.rb')
File.delete(ruby_file) rescue nil
system("ragel -R #{ragel_file}")

begin
  require File.join(ragel_dir, 'scanner.rb')
rescue LoadError
  raise $!
end

# ///////////////////////////////////////////////////////////
# Bacon
# ///////////////////////////////////////////////////////////

require 'bacon'
Bacon.extend(Bacon::TestUnitOutput)
Bacon.summary_on_exit

# Removing the extra noises in output, making bacon even less verbose !!
if ENV['MUTE_BACON'] == 'true'
  Bacon.extend(Module.new {

    def handle_requirement(description)
      unless (error = yield).empty?
        print error[0..0]
      end
    end

    def handle_summary
      puts "", "  %d tests, %d assertions, %d failures, %d errors" %
        Bacon::Counter.values_at(:specifications, :requirements, :failed, :errors)
    end

  })
end

# ///////////////////////////////////////////////////////////
# Spec helpers & matchers
# ///////////////////////////////////////////////////////////

def has_parsetree?
  Object.const_defined?(:ParseTree)
end

def watever(*args, &block)
  Proc.new(&block)
end

def code_to_sexp(code)
  if has_parsetree?
    require 'parse_tree'
    Unifier.new.process(ParseTree.translate(code))
  else
    require 'ruby_parser'
    RubyParser.new.parse(code)
  end
end

def normalize_code(code)
  Ruby2Ruby.new.process(code_to_sexp(code))
end

def having_source(expected, opts={})
  lambda do |_proc|
    normalize_code(_proc.to_source(opts)) == normalize_code(expected)
  end
end

def having_sexp(expected, opts={})
  lambda do |_proc|
    expected = eval(expected) if expected.is_a?(String)
    _proc.to_sexp(opts).inspect == expected.inspect
  end
end

def capture(stdin_str = '')
  begin
    require 'stringio'
    $o_stdin, $o_stdout, $o_stderr = $stdin, $stdout, $stderr
    $stdin, $stdout, $stderr = StringIO.new(stdin_str), StringIO.new, StringIO.new
    yield
    {:stdout => $stdout.string, :stderr => $stderr.string}
  ensure
    $stdin, $stdout, $stderr = $o_stdin, $o_stdout, $o_stderr
  end
end

def irb_exec(stdin_str)
  # See http://tyenglog.heroku.com/2010/9/how-to-test-irb-specific-support &
  # http://tyenglog.heroku.com/2010/9/how-to-test-irb-specific-support-2-
  sourcify_rb = File.join(File.expand_path(File.dirname(__FILE__)), '..', 'lib', 'sourcify.rb')
  irb_feedback = /^ => /
  values = %x(echo "#{stdin_str}" | irb -r #{sourcify_rb}).split("\n").
    grep(irb_feedback).map{|s| eval(s.sub(irb_feedback,'').strip) }
  # IRB behaves slightly differently in 1.9.2 for appending newline
  (values[-1].nil? && RUBY_VERSION.include?('1.9.2')) ? values[0 .. -2] : values
end

