# typed: strict

module FogBackup
  # Careful subprocess wrapper for the backup toolchain (pg_dump, pg_restore,
  # tar) — trimmed port of feed's Media::ToolRunner. Explicit argv (never a
  # shell string), a hard timeout, bounded output capture, and the child
  # killed by process group so a wedged dump dies with its parent.
  module Shell
    extend T::Sig

    class Error < StandardError; end
    class Timeout < Error; end

    DEFAULT_TIMEOUT = T.let(3600, Integer)
    MAX_OUTPUT_BYTES = T.let(256 * 1024, Integer)

    class Result < T::Struct
      extend T::Sig

      const :status, Integer
      const :stdout, String
      const :stderr, String

      sig { returns(T::Boolean) }
      def success? = status.zero?
    end

    sig { params(argv: T::Array[String], timeout: Integer, env: T::Hash[String, String]).returns(Result) }
    def self.run(argv, timeout: DEFAULT_TIMEOUT, env: {})
      out_r, out_w = IO.pipe
      err_r, err_w = IO.pipe

      pid = T.unsafe(Process).spawn(env, *argv, out: out_w, err: err_w, pgroup: true)
      out_w.close
      err_w.close

      readers = [ reader_thread(out_r), reader_thread(err_r) ]
      waiter = Thread.new { Process.waitpid2(pid) }

      if waiter.join(timeout).nil?
        kill_group(pid)
        readers.each { |thread| thread.join(5) }
        if waiter.join(5).nil?
          waiter.kill
          Process.detach(pid)
        end
        raise Timeout, "#{argv.first} exceeded #{timeout}s"
      end

      status = T.cast(waiter.value, [ Integer, Process::Status ])[1]
      Result.new(
        status: status.exitstatus || -1,
        stdout: readers.fetch(0).value.to_s,
        stderr: readers.fetch(1).value.to_s
      )
    ensure
      [ out_r, err_r ].each { |io| io.close unless io.nil? || io.closed? }
    end

    sig { params(io: IO).returns(Thread) }
    def self.reader_thread(io)
      Thread.new do
        buffer = +""
        begin
          while (chunk = io.read(65_536))
            buffer << chunk if buffer.bytesize < MAX_OUTPUT_BYTES
          end
        rescue IOError
          nil
        end
        buffer
      end
    end
    private_class_method :reader_thread

    sig { params(pid: Integer).void }
    def self.kill_group(pid)
      group = Process.getpgid(pid)
      Process.kill("-TERM", group)
      20.times do
        sleep 0.1
        Process.getpgid(pid)
      end
      Process.kill("-KILL", group)
    rescue Errno::ESRCH, Errno::EPERM
      nil
    end
    private_class_method :kill_group
  end
end
