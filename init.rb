Redmine::Plugin.register :redmine_reformat do
  name 'Redmine richtext conversion plugin'
  author 'Martin Cizek, Orchitech Solutions'
  author_url 'https://orchi.tech/'
  description 'Rake task providing configurable format conversions.'
  version '0.7.0'
  hidden true if respond_to? :hidden

  requires_redmine version_or_higher: '3.4.0'
end
