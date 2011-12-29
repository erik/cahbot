#!/usr/bin/env ruby

require 'cinch'

def reload_cards()
	$white_cards = File.open("white.txt").readlines().join.split("\n").shuffle
	$black_cards = File.open("black.txt").readlines().join.split("\n").shuffle
end

class Player
	attr_accessor :white_cards, :black_cards, :user, :picked_card, :selected
	attr_accessor :name
	attr_accessor :score
	attr_accessor :id
	

	def initialize(user)
		@user = user
		@name = user.nick
		@white_cards = []
		@black_cards = []
		@score = 0
		@id = 0
		@picked_card = false
		@selected = []
	end

	def print_player(pts=true, picked=false)
		"#{@name} #{" --DIDN'T PICK CARDS YET-- " if picked and not @picked_card and @name != $game.czar.name }(#{@score} points)"
	end

end

class CAHGame
	attr_accessor :game_state, :players, :czar, :creator, :round_in_progress,
		:black_card, :channel, :next_players, :card_map

	def initialize()
		@players = []
		@game_state = :nothing
		@czar = nil
		@creator = ""
		@round_in_progress = false
		@next_players = []
		@black_card = {:card => nil, :blanks => 0}
		@card_map = {}
		@m = nil
	end

	def start_round()
		@players += @next_players
		@round_in_progress = true

		old = @czar

		loop do
			@czar = @players.sample
			break if @czar != old
		end

		@czar.user.notice("Hey, you're the card czar for this round. " +
			"Sit back and relax for a second while the others choose cards.")

		black = $black_cards.shift
		@black_card = { :card => black, :blanks => black.count("_") }


		@m.reply "Our Card Czar this round is #{@czar.name}. " +
			"The black card is '#{@black_card[:card]}' (#{@black_card[:blanks]} blank(s))"

		deal_round()
	end

	def pick_card(m, i)
		p = nil
		@players.each do |player|
			m.reply "You can't do that! You're the Card Czar!" and return false if m.user.nick == @czar.name
			p = player and break if player.name == m.user.nick		
		end

		m.reply "You're not in the game, #{m.user.nick}! ^join to join it." and return if not p

			
		p.selected << i
		m.reply "Too many cards #{m.user.nick}! I'm removing that last one for you" \
			and p.selected.pop if p.selected.size > @black_card[:blanks]
		p.picked_card = true if p.selected.size == @black_card[:blanks]

		@players.each do |player|
			return :round_on if not player.picked_card and player.name != @czar.name
		end

		:round_over
	end

	def add_player(user)
		@players.each do |p|
			return false if p.name == user.nick
		end

		@players << Player.new(user) if @game_state == :lobby
		@next_players << Player.new(user) if @game_state == :play
		true
	end

	def start_lobby(message)
		@game_state = :lobby
		@creator = message.user.nick
		@channel = message.channel
	end

	def start_game(m)
		@game_state = :play
		@m = m
	end

	def stop_game()
		@game_state = :nothing
		@players = []
		@czar = nil
		@creator = ""
	end

	def deal_round()
		@players.each do |player|
			next if player.name == @czar.user.nick
	
			player.selected = []
			player.picked_card = false

			while player.white_cards.size < 10 do
				reload_cards if $white_cards.empty?

				player.white_cards << $white_cards.shift
			end

			str = "Your cards for this round are: "

			i = 0
			player.white_cards.each { |c|
				i += 1
				str += "(#{i}) - #{c} ::: "
			}

			str += "When you're ready, send me '^pick <cardnumbers>' in #{@channel}"

			player.user.notice(str)
		end
	end

	def print_players(a=true, b=false)
		return "It seems that everyone is a loser. No one joined #{@creator}'s awesome game" if @players.size == 0

		@players.map {|player| player.print_player(a, b)}.join(", ")
	end

	def pick_winner(id)

		p = nil

		@players.each do |player|
			@m.reply "HEY WOAH. Take it easy man. Give them a chance to pick some cards" and \
				return if not player.picked_card and player.name != @czar.name
		end

		@players.each do |player|
			next if player.name == @czar.name
			p = player if player.id == id	
		end

		@m.reply "I don't know who #{id} is supposed to be, but they're not here" and return if not p
		
		i = 0
		@black_card[:card].gsub!("_") {
			i += 1
			c = p.selected[i - 1] - 1
			p.white_cards[c]
		}

		@m.reply "We have a winner! #{p.name} said \"#{@black_card[:card]}\""
		p.score += 1

		@players.each do |player|
			remove = []
			player.selected.each {|x|
				remove << player.white_cards[x - 1]
			}

		player.white_cards -= remove

		end

		start_round
	end

	def send_choices()
		@m.reply("'#{@black_card[:card]}'")

		ids = (1..@players.size).to_a
		@players.shuffle

		@players.each do |player|
			next if player.name == @czar.name
			
			player.id = ids.shift

			cards = []

			player.selected.each { |x|
				cards << player.white_cards[x - 1]
			}
			
			@m.reply("#{player.id}: #{cards.join(", ")}")
		end

		@m.reply("Choose wisely (^winner <id>)")

	end

end

$nick = "cahbawt"

$bot = Cinch::Bot.new do
  configure do |c|
		c.nick = $nick
    c.server = "irc.freenode.net"
    c.channels = ["##cardsagainsthumanity-bots"]
  end

	on :message, "^create" do |m|
		if $game.game_state == :nothing then
			$game.start_lobby m
			m.reply "Lobby started for #{$game.channel}, type ^join to join the game, and ^start to start the game"
		else
			m.reply "Game already in progress, ^stop to stop it"
		end
	end

	on :message, "^stop" do |m|
		if $game.game_state == :nothing then
			m.reply "No game in progress, ^create to start one"
		else
			if m.user.nick == $game.creator then
				m.reply "I had a blast, didn't you? Then #{m.user.nick} had to go and kill it."
				$game.stop_game
			else
				m.reply "Silly #{m.user.nick}, you aren't the game creator"
			end
		end
	end

	on :message, "^reload" do |m|
		m.reply "Don't worry #{m.user.nick}, I'll implement this eventually"
	end

	on :message, "^join" do |m|
		if $game.game_state == :nothing then
			m.reply "No game in progress, ^create to start one"
		end
		if $game.game_state != :nothing then
			if $game.add_player(m.user) then
				m.reply "#{m.user.nick} is in" +
					"#{" starting next round" if $game.game_state == :play}."
			else
			  m.reply "#{m.user.nick} really really wants to play, hurry it up, #{$game.creator}!"
			end
		end
	end

	on :message, /\^boot (.*)/ do |m, name|
		m.reply "Can't kick yourself #{name}, use ^leave" and return if m.user.nick == name
		m.reply "NO." and return if m.user.nick != $game.creator

		$game.players.delete_if { |p| p.name == name }

		m.reply "Okay, #{name} is out."
	end

	on :message, /^\^pick .*/ do |m|
		status = :wut
		m.message.scan(/([0-9]+)/).each { |s|
			i = s[0].to_i

			if i > 10 or i < 1 then
				m.reply "Pick a number 1-10, smartass."
				return
			end

			status = $game.pick_card(m, i)
			return if not status
		}

		m.reply "Duly noted, #{m.user.nick}"

		if status == :round_over then
			m.reply "Everyone's selections are in! #{$game.czar.name}, go ahead and pick a winner"
			$game.send_choices
		end
	end

	on :message, /^\^winner .*/ do |m|
		id = m.message.match(/\^winner ([0-9]+)/)[1]
		id = id.to_i

		if $game.game_state != :play then
			m.reply "No game in progress. Start one if you'd like."
			return
		end

		if not $game.round_in_progress then
			m.reply "No round is in progress right now. ...somehow."	
			return
		end

		if $game.czar.name != m.user.nick then
			m.reply "Only the Card Czar for this round, #{$game.czar.name}, can pick a winner"
		end

		$game.pick_winner id
	end

	on :message, "^next" do |m|
		$game.start_round
	end

	on :message, "^help" do |m|
		m.user.notice "Here are some things that "
	end

	on :message, "^start" do |m|
		if $game.game_state != :lobby then
			m.reply "Game should be in lobby to start"
		else
				if m.user.nick != $game.creator then
					m.reply "Only the glorious creator #{$game.creator} in all his infinite wisdom may start the game"
				elsif $game.players.size < 2 then
					m.reply "You need to have at least 2 players to start the game, but it doesn't really make" +
						" sense with less than 3, now does it?"
				else
					m.reply "Okay, let's do this. #{$game.creator}'s game beginning with the " +
						"following players: #{$game.print_players}"
					$game.start_game(m)
					$game.start_round
				end
		end
	end

	on :message, /^\^bother .*/ do |m|
		if $game.game_state == :nothing then
			m.reply "Hey #{m.user.nick}, there isn't a game going on right now you twat."
		else
			m.reply "Hey #{m.message.match(/\^bother (.*)/)[1]}, join the fucking game"
		end
	end

	on :message, "^players" do |m|
		if $game.game_state == :nothing then
			m.reply "Seems that nothing exciting is happening, why don't you start a game, it'll be great!"
		else
			m.reply "#{$game.print_players true, true}" if $game.game_state == :play
			m.reply "#{$game.print_players}" if $game.game_state == :lobby
		end
	end

	on :message, "^leave" do |m|
		m.reply "Fuck you #{m.user.nick}, you cannot abandon this game!"
	end

	on :message, /#{$nick}:([0-9]+)/ do |m|
		
	end

	on :message, "^" do |m|
		m.reply "Motherfucker had like 30 goddamn dicks"
	end

	on :message, "random" do |m|
		m.reply $white_cards[rand($white_cards.size)]
	end

  on :message, "hello" do |m|
    m.reply "Hello, #{m.user.nick}"
  end
end

reload_cards()
$game = CAHGame.new
$bot.start
