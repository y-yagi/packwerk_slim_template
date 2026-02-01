# PackwerkSlim

PackerSlim supports Slim templates in [Packwerk](https://github.com/Shopify/packwerk)

## Installation

Add the gem to your application's `Gemfile`:

```ruby
gem "packwerk_slim"
```

Then install it:

```bash
bundle install
```

## Usage

1. Ensure Packwerk knows it should scan Slim files. Update `config/packwerk.yml` (or your equivalent Packwerk configuration) so the `include` list contains Slim alongside the existing extensions:

    ```yaml
    include:
      - "**/*.{rb,rake,erb,slim}"
    ```

2. Run Packwerk as usual:

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then run `bundle rake test` to execute the test suite. You can also run `bin/console` for an interactive prompt that lets you experiment with the converters.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/y-yagi/packwerk_slim. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/y-yagi/packwerk_slim/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the PackwerkSlim project's codebases, issue trackers, chat rooms, and mailing lists is expected to follow the [code of conduct](https://github.com/y-yagi/packwerk_slim/blob/main/CODE_OF_CONDUCT.md).
