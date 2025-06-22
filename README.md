# WeatherVoting

A Minecraft Spigot plugin that allows players to vote on changing the current weather in the server.

[![SpigotMC](https://img.shields.io/badge/SpigotMC-WeatherVoting-orange)](https://www.spigotmc.org/resources/weathervoting.122848/)
[![Donate](https://img.shields.io/badge/Donate-PayPal-blue.svg)](https://www.paypal.com/paypalme/mckenzio)

## Features

* 🗳️ Players can vote to change the current weather in the server
* 📊 Configurable voting threshold based on percentage of online players
* ⏱️ Cooldown system prevents spam voting and frequent weather changes
* ⌛ Control how long each weather type lasts after being voted in
* 📢 Broadcast announcements when players vote for weather changes
* 🔮 Weather forecast command to check current weather and time until natural change
* 💬 Fully customizable messages for all plugin text

## Installation

1. Download the latest release from [Spigot](https://www.spigotmc.org/resources/weathervoting.122848/) or [GitHub Releases](https://github.com/McKenzieJDan/WeatherVoting/releases)
2. Place the JAR file in your server's `plugins` folder
3. Restart your server
4. Configure the plugin in the `config.yml` file

## Usage

Players can vote for their preferred weather type using simple commands. When enough players vote for a specific weather, it will change automatically.

### Commands

* `/voteweather` - Shows the current vote status
* `/voteweather sunny` - Vote for sunny weather
* `/voteweather rain` - Vote for rainy weather
* `/voteweather thunder` - Vote for thunderstorm weather
* `/forecast` - View the current weather and when it will change naturally

### Permissions

* `weathervoting.vote` - Permission to vote for weather changes
* `weathervoting.forecast` - Permission to use the forecast command

## Configuration

The plugin's configuration file (`config.yml`) is organized into logical sections:

```yaml
# Percentage of online players needed to change the weather
voting:
  threshold-percentage: 50

# Cooldown settings to prevent spam
cooldowns:
  between-changes: 300
  between-votes: 60
```

For detailed configuration options, see the comments in the generated config.yml file.

## Requirements

- Java 21+
- Spigot/Paper 1.21.6

## Used By

[SuegoFaults](https://suegofaults.com) - A mature Minecraft community where WeatherVoting gives players shared control over the skies.


## Support

If you find this plugin helpful, consider [buying me a coffee](https://www.paypal.com/paypalme/mckenzio) ☕

## License

[MIT License](LICENSE)

Made with ❤️ by [McKenzieJDan](https://github.com/McKenzieJDan)