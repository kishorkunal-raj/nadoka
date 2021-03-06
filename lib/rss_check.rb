#
# Copyright (c) 2004-2005 SASADA Koichi <ko1 at atdot.net>
#
# This program is free software with ABSOLUTELY NO WARRANTY.
# You can re-distribute and/or modify this program under
# the same terms of the Ruby's license.
#
# 
# $Id$
# Create : K.S. Sat, 24 Apr 2004 12:10:31 +0900
#

require "rss/parser"
require "rss/1.0"
require "rss/2.0"
require "rss/syndication"
require "rss/dublincore"
require "open-uri"
require 'uri'
require 'yaml/store'
require 'csv'
require 'stringio'
require 'zlib'


class RSS_Check
  class RSS_File
    def initialize path, init_now
      @uri = URI.parse(path)
      @entry_time = @file_time = (init_now ? Time.now : Time.at(0))
    end
    
    def check
      begin
        if (mt=mtime) > @file_time
          @file_time = mt
          check_entries
        else
          []
        end
      rescue => e
        [{
          :about => e.message,
          :title => "RSS Check Error (#{@uri})",
          :ccode => 'UTF-8'
        }]
      end
    end

    def date_of e
      if e.respond_to? :dc_date
        e.dc_date || Time.at(0)
      else
        e.pubDate || Time.at(0)
      end
    end
    
    def check_entries
      rss = RSS::Parser.parse(read_content, false)
      et = @entry_time
      items = rss.items.sort_by{|e|
        date_of(e)
      }.map{|e|
        e_date = date_of(e)
        if e_date > @entry_time
          if e_date > et
            et = e_date
          end
          {
            :about => e.about,
            :title => e.title,
            :ccode => 'UTF-8'
          }
        end
      }.compact
      @entry_time = et
      items
    end

    def read_content
      case @uri.scheme
      when 'http', 'https'
        open(@uri){|f|
          if f.content_encoding.any?{|e| /gzip/ =~ e}
            Zlib::GzipReader.new(StringIO.new(f.read)).read || ''
          else
            f.read
          end
        }
      else
        open(@uri.to_s){|f|
          f.read
        }
      end
    end

    def mtime
      case @uri.scheme
      when 'http', 'https'
        open(@uri){|f|
          f.last_modified || Time.now
        }
      else
        File.mtime(@rss_file)
      end
    end
  end

  class LIRS_File < RSS_File
    def check_entries
      et = @entry_time
      res = []
      CSV::Reader.parse(read_content){|row|
        last_detected = Time.at(row[2].data.to_i)
        if last_detected > @entry_time && row[1].data != row[2].data
          if last_detected > et
            et = last_detected
          end
          res << {
            :about => row[5].data,
            :title => row[6].data,
            :ccode => 'EUC-JP'
          }
        end
      }
      @entry_time = et
      res
    end
  end
  
  def initialize paths, cache_file=nil, init_now=false
    @paths = paths
    @db = YAML::Store.new(cache_file) if cache_file
    @rss_files = paths.map{|uri|
      load_file(uri) ||
        if /LIRS:(.+)/ =~ uri
          LIRS_File.new($1, init_now)
        else
          RSS_File.new(uri, init_now)
        end
    }
  end

  def check
    @rss_files.map{|rf|
      rf.check
    }.flatten
  end

  def save
    debug = $DEBUG
    $DEBUG = false
    @db.transaction{
      @paths.each_with_index{|path, i|
        @db[path] = @rss_files[i]
      }
    } if @db
  ensure
    $DEBUG = debug
  end

  def load_file file
    debug = $DEBUG
    $DEBUG = false
    @db.transaction{
      @db[file]
    } if @db
  ensure
    $DEBUG = debug
  end

  def clear
    debug = $DEBUG
    $DEBUG = false
    if @db
      @db.transaction{
        @db.keys.each{|k|
          @db.delete k
        }
      }
    end
  ensure
    $DEBUG = debug
  end
end


if $0 == __FILE__
  rss_uri = %w(
    http://www.ruby-lang.org/ja/index.rdf
    http://slashdot.jp/slashdotjp.rss
    http://www3.asahi.com/rss/index.rdf
    http://pcweb.mycom.co.jp/haishin/rss/index.rdf
    http://japan.cnet.com/rss/index.rdf
    http://blog.japan.cnet.com/umeda/index.rdf
    http://jvn.doi.ics.keio.ac.jp/rss/jvnRSS.rdf
  )
  lirs_uri = [
  'LIRS:http://www.rubyist.net/~kazu/samidare/sites.lirs.gz'
  ]
  
  rssc = RSS_Check.new(
    rss_uri + lirs_uri,
    ARGV.shift || './rss_cache',
    false # false
  )
  require 'kconv'
  
  rssc.check.each{|e|
    puts e[:about]
    title = (e[:ccode] == 'UTF-8') ? e[:title].toeuc : e[:title]
    puts title
  }
  rssc.dump
end

