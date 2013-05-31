require 'pp'
require 'csv'
require 'cgi'
require 'json'
require 'diff/lcs'
require 'net/http'
require 'bigdecimal'

class Array
   def symbolize_keys! skip=[]
      self.each_with_index do |val,idx|
         # If it's a Array or a Hash, call the same symbolize_keys! method.
         self[idx].symbolize_keys! skip if [ Array, Hash ].include? self[idx].class

         # Strip any trailing spaces/newlines
         self[idx] = self[idx].strip    if self[idx].is_a? String

         # If it's a String, but it's a number, this will convert it to a number
         self[idx] = self[idx].to_i     if self[idx].is_a? String and self[idx].to_i.to_s == self[idx]
      end
      self
   end
end

class Hash
   def symbolize_keys! skip=[]
      keys.each do |key|
         #puts "KEY(#{skip}): #{key} -> #{skip.each{|k| k}}"
         #puts "FOUND IT:#{key}" if skip.include? key.downcase # Movies like "300" get converted to FixNum and search breaks
         unless skip.include? key
            #self[key].symbolize_keys! flatten if [ Array, Hash ].include? self[key].class
            self[key].symbolize_keys! skip if [ Array, Hash ].include? self[key].class
            if self[key].is_a? Array
              #puts "KEY: #{key} #{self[key].size} ##{self[key].first}# <- ##{self[key]}#" if self[key].size == 1
              self[key] = self[key].first if self[key].size == 1
            end
         end
         self[(key.to_sym rescue key) || key] = delete(key)
      end
      self
   end
end

module Vudu
class Disc2Digital
   attr_reader :id, :barcode, :title, :disc_type, :year, :unknown, :length, :director, :unknown_2
   attr_reader :entries, :first, :last, :next, :previous
   attr_accessor :entry, :http, :parse, :parse_json, :push, :pos, :match, :raw_entry, :total_count, :same_quality, :upgrade_quality, :ultraviolet

   @@pos     = 0
   @@entry   = nil
   @@match   = 0
   @@entries = Array.new
   @@header  = [ :id, 'barcode', :title, :disc_type, :year, :unknown, :length, :director, :unknown_2 ]

   @@ultraviolet     = 0 # How many movies we can upgrade
   @@total_count     = 0
   @@same_quality    = 0
   @@upgrade_quality = 0

   def initialize file
      #@@id, @@barcode, @@title, @@disc_type, @@year, @@unknown, @@length, @@directory, @@unknown_2 = csv.split(/,/).each_with_index{|entry,i| puts i; (i <= 1 or i == 4 or i == 6) ? 0 : i }
      #@@id, @@barcode, @@title, @@disc_type, @@year, @@unknown, @@length, @@directory, @@unknown_2 = csv.split(/,/).each_with_index{|entry,i| puts i; (i <= 1 or i == 4 or i == 6) ? 0 : i }

      begin
         #@@id, @@barcode, @@title, @@disc_type, @@year, @@unknown, @@length, @@directory, @@unknown_2 = CSV.parse(file).first
         #parsed = CSV.parse File.read(file)

         CSV.parse(File.read(file)).each{|movie|
            self.raw_entry = movie if self.raw_entry.nil?
            entry = self.parse movie
            @@entries << entry
         }
      rescue => e
         abort "ERROR: #{e.message}"
      end
   end

   def title
      @title
   end

   def parse movie
      entry = Hash.new

      movie.each_with_index{|e,i|
         h = @@header[i]
         ([ 0, 4, 6 ].include? i) ? entry[h] = e.to_i : entry[h] = e
      }

      entry
   end

   def entry num=nil

      return @@entry if @@entries[self.pos].nil?

      # Grab the entry with this number if it exists
      if not num.nil?
        entry = @@entries[num] unless @@entries[num].nil?

      # If no number was specified and @@entry is nil, grab the first entry.
      elsif @@entry.nil?
        entry = self.first

      # If @@entry has something, we want to work with it's current value.
      else
        entry = @@entry
      end

      # Split the stuffs up and set @@entry
      if not entry.nil?
        @id, @barcode, @title, @disc_type, @year, @unknown, @length, @directory, @unknown_2 = entry.values{|v| v}
        @disc_type.tr "-", "" # Change Blu-ray to Bluray since Vudu uses 'bluRay'
        @@entry = entry
      end

      @@entry
   end

   def entries
      @@entries
   end

   def total_count
      @@total_count
   end

   def first
      @@entries.first
   end

   def last
      @@entries.last
   end

   def match
      @@match
   end

   def next
     self.pos = pos + 1 # Increment the counter if there is something to increment to.
     pos = self.pos

     # If obj.next was called before anything else, grab the first entry.
     @@entry = self.first if pos == 0 and @@entry.nil?

     if @@entries[pos].nil?
        @@entry = nil # We appear to be out of entries, return nil
     else
        @@entry = @@entries[pos] # If this entry exists, grab it.
     end

     #@@entry = @@entries[pos] unless @@entries[pos].nil?
     #puts "@@entries[#{pos}] == #{@@entries[pos]} == #{@@entries[pos].class}"

     @@entry
   end

   def previous
     # Skip back 2 entries, the current one and the one we want to read in again.
     #
     # 0
     # v-== -2 gets us in front of the one we want.
     # 1
     # v-== -1 gets us in front of the current one
     # 2 
     # ^-== Current POS
     #
     pos = self.pos - 2

     @@entry = @@entries[pos] unless @@entries[pos].nil?
     self.pos = pos

     self.next

     @@entry
   end

   def pos
      @@pos 
   end

   def pos= pos
      @@pos = pos
   end

   def query title
      @@total_count = 0 # Reset back to zero so we don't get the last title's count

      vudu_api = 'http://apicache.vudu.com/api2/claimedAppId/myvudu/format/application*2Fjson/callback/DirectorSequentialCallback/_type/catalogItemTitleSearch/count/10/followup/totalCount/onlyConvertible/true/titleMagic/'
      vudu_api << CGI.escape(title)

      uri = URI.parse(vudu_api)
      req = Net::HTTP::Get.new(uri)

      req['Accept-Language'] = 'en-US,en;q=0.8'
      req['User-Agent'] = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_8_2) AppleWebKit/537.22 (KHTML, like Gecko) Chrome/25.0.1364.172 Safari/537.22'
      req['Referer'] = 'http://www.vudu.com/disc_to_digital.html'

      #req['Accept-Encoding'] = 'gzip,deflate,sdch'
      #req['Accept-Charset'] = 'ISO-8859-1,utf-8;q=0.7,*;q=0.3'

      #req['If-Modified-Since'] = file.mtime.rfc2822

      res = Net::HTTP.start(uri.hostname, uri.port) {|http|
        http.request(req)
      }

      res = self.parse_json res.body
      res[:myMovie] = self.entry

      # DirectorSequentialCallback({"_type":"catalogItemTitleList","catalogItemTitle":[{"_type":"catalogItemTitle","catalogItemId":["240935"],"contentId":["5710"],"discType":["bluRay"],"sameQualityContentVariantId":["162841"],"sameQualityLabel":["hdx"],"sameQualityPrice":["2"],"sameQualityWalmartUpc":["68113103688"],"title":["Bourne Identity "],"year":["2002"]},{"_type":"catalogItemTitle","catalogItemId":["240934"],"contentId":["5710"],"discType":["dvd"],"sameQualityContentVariantId":["146743"],"sameQualityLabel":["sd"],"sameQualityPrice":["2"],"sameQualityWalmartUpc":["60538803606"],"title":["Bourne Identity "],"upgradeQualityContentVariantId":["162841"],"upgradeQualityLabel":["hdx"],"upgradeQualityPrice":["5"],"upgradeQualityWalmartUpc":["60538803611"],"year":["2002"]},{"_type":"catalogItemTitle","catalogItemId":["212456"],"contentId":["5710"],"discType":["bluRay"],"sameQualityContentVariantId":["162841"],"sameQualityLabel":["hdx"],"sameQualityPrice":["2"],"sameQualityWalmartUpc":["68113103688"],"title":["The Bourne Identity "],"year":["2002"]},{"_type":"catalogItemTitle","catalogItemId":["123619"],"contentId":["5710"],"discType":["dvd"],"sameQualityContentVariantId":["146743"],"sameQualityLabel":["sd"],"sameQualityPrice":["2"],"sameQualityWalmartUpc":["60538803606"],"title":["The Bourne Identity "],"upgradeQualityContentVariantId":["162841"],"upgradeQualityLabel":["hdx"],"upgradeQualityPrice":["5"],"upgradeQualityWalmartUpc":["60538803611"],"year":["2002"]}],"moreAbove":["false"],"moreBelow":["false"],"zoom":[{"_type":"zoomData","doItMsec":["82"],"servletMsec":["81","84"]}]})

      #pp res['catalogItemTitle']
      # Do all the keys except for catalogItemTitle, because we need to retain the array of titles.
      res.symbolize_keys! [ 'catalogItemTitle', :catalogItemTitle ]

      # We will however, do all the keys under the key catalogItemTitle
      res[:catalogItemTitle].symbolize_keys! unless res[:catalogItemTitle].nil?

      # Loop through the entries and find the best match.
#      res[:catalogItemTitle].each{|movie|
#         self.match = 0 # Reset the match for each title
         #puts "MOVIE: #{movie}"
         # Keep looking for our media type.  IE - Bluray, DVD, HD DVD
         #puts "YAYAY: discType: #{movie[:discType]} -> #{self.disc_type}"
       
         #if 1 == 0 # Non-flattened Arrays
#         next unless movie[:discType][0].downcase.strip == self.disc_type.downcase.strip
#
#         # Convert the title to String just in case the movie was all numeric (300).  Then try a straight compare first
#         if movie[:title][0].to_s.downcase.strip == self.title.downcase.strip
#            puts "\tFOUND A PERFECT MATCH FOR #{self.title} #{movie[:title][0]} (#{self.disc_type})"
#            self.match = 100
#         else
#            lcs = Diff::LCS.LCS(movie[:title][0].downcase.strip, self.title.downcase.strip).join # Longest common substring
#            percentage = (lcs.size / self.title.size) * 100
#        
#            puts "PERCENTAGE: #{percentage}"
#            if percentage >= 70
#               puts "\tFOUND #{percentage}% MATCH FOR: #{self.title} #{movie[:title][0]} (#{self.disc_type})"
#               next
#            end
#            # No matching strings at all
#            if lcs.size == 0
#               puts "\tFOUND ZERO MATCHES FOR: #{self.title} #{movie[:title][0]} (#{self.disc_type})"
#               next
#            elsif percentage >= 70
#               puts "\tFOUND #{percentage}% MATCH FOR: #{self.title} #{movie[:title][0]} (#{self.disc_type})"
#               next
#            end
#           
#            #movie['title'].strip.size Diff::LCS.LCS(movie['title'].strip, self.title.strip).size
#         end
         #else

      # Loop through the entries and find the best match.
      res[:catalogItemTitle].each{|movie|
         self.match = 0 # Reset the match for each title

         next unless movie[:discType].downcase.strip == self.disc_type.downcase.strip

         # Convert the title to String just in case the movie was all numeric (300).  Then try a straight compare first
         if movie[:title].to_s.downcase.strip == self.title.downcase.strip
            #puts "if #{movie[:title].to_s.downcase.strip} == #{self.title.downcase.strip} - #{self.disc_type}"
            puts "PERFECT MATCH FOR: #{self.title} #{movie[:title]} (#{self.disc_type}): "

            [ :sameQualityPrice, :sameQualityLabel, :upgradeQualityPrice, :upgradeQualityLabel ].each{|key|
               puts "#{key}:".rjust(25) + " #{movie[key].to_s.upcase}" if not movie[key].nil?

               #self.same_quality    = self.same_quality + movie[key].to_i    if [ :sameQualityPrice ].include? key
               #self.upgrade_quality = self.upgrade_quality + movie[key].to_i if [ :upgradeQualityPrice ].include? key
               self.same_quality    += movie[key].to_i if [ :sameQualityPrice ].include? key
               self.upgrade_quality += movie[key].to_i if [ :upgradeQualityPrice ].include? key
            }

            #self.ultraviolet = 1
            self.ultraviolet += 1

            puts "Ultraviolet Movies:".rjust(25) + " #{@@ultraviolet}"
            puts "Same quality cost: ".rjust(25) + "$#{self.same_quality}"
            puts "Upgrade quality cost: ".rjust(25) + "$#{self.upgrade_quality}"

            puts "\n" + "-"*80
            self.match = 100

            break
         else
            lcs = Diff::LCS.LCS(movie[:title].downcase.strip, self.title.downcase.strip).join # Longest common substring
            percentage = BigDecimal((lcs.size / self.title.size) * 100)
        
            #if percentage >= 70
            #   puts "\tFOUND #{percentage}% MATCH FOR: #{self.title} #{movie[:title]} (#{self.disc_type})"
            #   next
            #end

            # No matching strings at all
            #if lcs.size == 0
            #   puts "\tFOUND ZERO MATCHES FOR: #{self.title} #{movie[:title]} (#{self.disc_type})"
            #   next
            #elsif percentage >= 70
            #   puts "\tFOUND #{percentage}% MATCH FOR: #{self.title} #{movie[:title]} (#{self.disc_type})"
            #   next
            #end

            if percentage >= 70.0
               puts "\tFOUND #{percentage}% MATCH FOR: #{self.title} #{movie[:title]} (#{self.disc_type})"

              [ :sameQualityPrice, :sameQualityLabel, :upgradeQualityPrice, :upgradeQualityLabel ].each{|key|
                 puts "#{key}:".rjust(25) + " #{movie[key].to_s.upcase}" if not movie[key].nil?

                 self.same_quality    += movie[key].to_i if [ :sameQualityPrice ].include? key
                 self.upgrade_quality += movie[key].to_i if [ :upgradeQualityPrice ].include? key
                 #self.same_quality    = self.same_quality + movie[key].to_i    if [ :sameQualityPrice ].include? key
                 #self.upgrade_quality = self.upgrade_quality + movie[key].to_i if [ :upgradeQualityPrice ].include? key
              }

              #self.ultraviolet = (@@ultraviolet + 1)
              self.ultraviolet += 1

              puts "Ultraviolet Movies:".rjust(25) + " #{@@ultraviolet}"
              puts "Same quality cost: ".rjust(25) + "$#{self.same_quality}"
              puts "Upgrade quality cost: ".rjust(25) + "$#{self.upgrade_quality}"

              puts "\n" + "-"*80
              self.match = percentage
  
              break
            end
            #movie['title'].strip.size Diff::LCS.LCS(movie['title'].strip, self.title.strip).size

         end
      } if res[:totalCount].to_i > 0

      @@total_count = res[:totalCount].to_i unless res[:totalCount].nil?

      res
   end

   def parse_json vudu_json
      #JSON.pretty_generate JSON::load(vudu_json.scan(/^DirectorSequentialCallback\((.*})\)$/).each{|m| m }.first.first)
      JSON.load(vudu_json.scan(/^DirectorSequentialCallback\((.*})\)$/).each{|m| m }.first.first)
   end

   # Reset the @@entry -> self.entry to nil
   def reset
      @@entry = nil
   end

   def parse_json vudu_json
      #JSON.pretty_generate JSON::load(vudu_json.scan(/^DirectorSequentialCallback\((.*})\)$/).each{|m| m }.first.first)
      JSON.load(vudu_json.scan(/^DirectorSequentialCallback\((.*})\)$/).each{|m| m }.first.first)
   end

   # Reset the @@entry -> self.entry to nil
   def reset
      @@entry = nil
   end

   def same_quality
      @@same_quality
   end

   def upgrade_quality
      @@upgrade_quality
   end

   def same_quality= num
      @@same_quality = num
   end

   def upgrade_quality= num
      @@upgrade_quality = num
   end

   def ultraviolet
      @@ultraviolet
   end

   def ultraviolet= num
      @@ultraviolet = num
   end

end
end

#
# ID,BARCODE,"TITLE","DISC_TYPE",YEAR,UNKNOWN,LENGTH,"DIRECTOR","UNKNOWN"
#
# 16,085391139683,"10,000 BC","DVD",2008,tt0443649,110,"Roland Emmerich","null"
# 530,786936735413,"101 Dalmatians","DVD",1961,tt0115433,79,"Rod Taylor","null"
# 123,025195024488,"12 Monkeys / Mercury Rising / The Jackal (Triple Feature)","DVD",1995,tt0114746,367,"Terry Gilliam","null"
# 17,012569736634,"300","DVD",2007,tt0416449,116,"Zack Snyder","null"
# 476,031398221852,"3:10 to Yuma","DVD",2007,tt0381849,122,"James Mangold","null"
# 92,025192145025,"A Beautiful Mind [Un homme d'exception]","DVD",2001,tt0268978,136,"Ron Howard","null"
# 396,024543407010,"A Good Year","DVD",2006,tt0401445,118,"Ridley Scott","null"

#
# Entry with no matches:
#
# DirectorSequentialCallback({"_type":"catalogItemTitleList","moreAbove":["false"],"moreBelow":["false"],"totalCount":["0"],"zoom":[{"_type":"zoomData","doItMsec":["184"],"servletMsec":["184","186"]}]})
#
# Entry WITH matches:
#
# DirectorSequentialCallback({"_type":"catalogItemTitleList","catalogItemTitle":[{"_type":"catalogItemTitle","catalogItemId":["191340"],"contentId":["132100"],"discType":["bluRay"],"sameQualityContentVariantId":["163193"],"sameQualityLabel":["hdx"],"sameQualityPrice":["2"],"sameQualityWalmartUpc":["68113103685"],"title":["10,000 B.C. "],"year":["2008"]},{"_type":"catalogItemTitle","catalogItemId":["191341"],"contentId":["132100"],"discType":["dvd"],"sameQualityContentVariantId":["154754"],"sameQualityLabel":["sd"],"sameQualityPrice":["2"],"sameQualityWalmartUpc":["60538803603"],"title":["10,000 B.C."],"upgradeQualityContentVariantId":["163193"],"upgradeQualityLabel":["hdx"],"upgradeQualityPrice":["5"],"upgradeQualityWalmartUpc":["60538803608"],"year":["2008"]}],"moreAbove":["false"],"moreBelow":["false"],"totalCount":["2"],"zoom":[{"_type":"zoomData","doItMsec":["78"],"servletMsec":["78","80"]}]})
#

# EOF
