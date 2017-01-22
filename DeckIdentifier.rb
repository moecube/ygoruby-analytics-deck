require File.dirname(__FILE__) + '/DeckType.rb'
require File.dirname(__FILE__) + '/Tag.rb'
require File.dirname(__FILE__) + '/Compiler.rb'

class DeckIdentifier
	attr_accessor :environment_name
	
	def initialize(name = 'mysterious')
		@tags             = []
		@global_tags      = []
		@decks            = []
		@environment_name = name
	end

	def classificationize(obj)
			if obj.is_a? Array
				obj.map { |child| classificationize child }
			elsif obj.is_a? Hash
				type = obj['type']
				type = type.downcase unless type == nil
				if type == nil
					logger.warn 'no type obj: ' + obj.inspect
					nil
				elsif type == 'deck'
					DeckType.from_json obj
				elsif type == 'tag'
					Tag.from_json obj
				else
					logger.warn "can't recognize type #{type}"
					nil
				end
			else
				logger.warn "can't recognize classification #{obj}"
				nil
			end
	end
	
	def register(obj)
		if obj.is_a? Array
			logger.info "#{environment_name} Loaded #{obj.count} definitions."
			obj.each { |child| register child }
		elsif obj.is_a? DeckType
			# logger.info "#{environment_name} Loaded 1 deck definition: #{obj.name}"
			@decks.push obj
		elsif obj.is_a? Tag
			# logger.info "#{environment_name} Loaded 1 tag definition: #{obj.name}"
			@tags.push obj
			if obj.is_global?
				@global_tags.push obj
			end
		end
	end
	
	def register_dir(dir_path)
		files = Dir.glob File.join dir_path, '*.*'
		files.each { |file| self.register_file file }
	end
	
	def register_config
		config = $config[File.dirname __FILE__]['Definitions']
		config = [config] if config.is_a? String
		config = [] unless config.is_a? Array
		config.each { |path| register_dir path }
	end
	
	def register_file(file_path)
		basename = File.basename file_path
		extname  = File.extname file_path
		if basename.start_with? '#'
			logger.info "ignored loading file #{basename}"
			return
		end
		logger.info "Identifier #{@environment_name} is loading file #{basename}"
		case extname
			when '.json'
				str = File.open(file_path).read
				self.register_json_str str
			when '.yaml'
				str = File.open(file_path).read
				self.register_yaml_str str
			when '.deckdef'
				self.register_deckdef_file File.open file_path
			when '.rb'
				logger.warn "not supported now for ruby definition #{basename}"
				self.register_rb_file str
			else
				logger.warn "can't recognize file #{file_path}"
		end
	end
	
	def register_rb_file(file)
		# not supported now
	end
	
	def register_yaml_str(str)
		require 'yaml'
		root = YAML.load str
		register classificationize root
	end
	
	def register_json_str(str)
		require 'json'
		root = JSON.parse str
		register classificationize root
	end
	
	def register_deckdef_file(file)
		root = DeckIdentifierCompiler.new.compile_file file
		register classificationize root
	end
	
	def clear
		@tags.clear
		@global_tags.clear
		@decks.clear
	end
	
	def generate_tag_hash
		@tag_hash = {}
		@tags.each { |tag| @tag_hash[tag.name] = tag }
	end
	
	def search_raw_tags
		generate_tag_hash if @tag_hash == nil
		@decks.each do |deck|
			search_raw_tag_array deck.check_tags
			search_raw_tag_array deck.force_tags
			search_raw_tag_array deck.refused_tags
		end
	end
	
	def search_raw_tag_array(tag_array)
		tag_array.each_with_index do |tag, index|
			next unless tag.is_raw?
			tag_array[index] = @tag_hash[tag.name]
			logger.info "not found named tag #{tag.name}" if tag_array[index] == nil
		end
		tag_array.replace tag_array.select { |tag| tag != nil }
	end
	
	def sort!
		@decks.sort { |deckA, deckB| deckB.priority <=> deckA.priority }
		@global_tags.sort { |deckA, deckB| deckB.priority <=> deckA.priority }
	end
	
	def finish
		search_raw_tags
		sort!
	end
	
	def polymerize(tags)
		tags = tags.select { |tag| tag.can_upgrade? }
		return nil if tags.count == 0
		priority = tags[0].priority
		names    = []
		for tag in tags
			(priority - tag.priority <= 1) ? names.push(tag): break
		end
		names.join ''
	end
	
	def recognize(deck)
		# 卡组检查
		deck, tags  = recognize_deck deck
		# Tag 检查
		global_tags = recognize_tag deck
		# 若卡组检查没有结果，选择 Tag 能升级者拼成一个 deck 名
		deck        = polymerize global_tags if deck == nil
		# 若还是没有结果，谜
		return [] if deck == nil
		# 联合
		tags = [] if tags == nil
		tags += global_tags
		# 提取名字
		deck = deck.name unless deck.is_a? String
		tags = tags.map { |tag| tag.name }
		# 返回
		[deck, tags]
	end
	
	def [](deck)
		recognize deck
	end
	
	def recognize_deck(deck)
		for deck_type in @decks
			answer = deck_type[deck]
			return [deck_type, answer] if answer
		end
		nil
	end
	
	def recognize_tag(deck)
		@global_tags.select { |tag| tag[deck] }
	end
	
	@@global = DeckIdentifier.new 'global'
	
	def self.global
		return @@global
	end
	
	# 前台服务器用的 API 🚪
	def self.check_access_key(key)
		return nil if key == nil
		keys = $config[File.dirname __FILE__]['Access Keys']
		return nil unless keys.has_key? key
		keys[key]
	end
	
	def self.quick_access_key(key, app, description)
		user = check_access_key key
		if user == nil
			app.halt [403, 'wrong access key not in list']
			return
		else
			logger.info "[#{user}] #{description}"
		end
	end
	
	def self.config_first_dir
		config = $config[File.dirname __FILE__]['Definitions']
		config = config[0] if config.is_a? Array
		config
	end
	
	def self.get_config_file_list
		dir = self.config_first_dir
		Dir.glob(dir + '/*.deckdef').map { |file| File.basename file, '.deckdef'}
	end
	
	def self.get_config_file(file_name)
		file_name = file_name.gsub('..', '').gsub('/', '')
		file_name = File.join self.config_first_dir, file_name
		File.open(file_name) { |f| f.read }
	end
	
	def self.save_config_file_to(file_name, file_content)
		file_name = file_name.gsub('..', '').gsub('/', '')
		file_name = File.join self.config_first_dir, file_name
		File.open(file_name, 'w') { |f| f.write file_content }
	end
	
	def self.remove_config_file(file_name)
		file_name = file_name.gsub('..', '').gsub('/', '')
		file_name = File.join self.config_first_dir, file_name
		File.delete file_name
	end
end
