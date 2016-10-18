namespace :load do
  task :defaults do
    set :chewy_conditionally_reset, -> { true }
    set :chewy_path, -> { 'app/chewy' }
    set :chewy_env, -> { fetch(:rails_env, fetch(:stage)) }
    set :chewy_role, -> { :app }
    set :chewy_skip, -> { false }
    set :chewy_default_hooks, -> { true }
  end
end

namespace :deploy do
  before :starting, :check_chewy_hooks do
    invoke :'deploy:chewy:add_default_hooks' if fetch(:chewy_default_hooks)
  end

  namespace :chewy do
    # Adds default Capistrano::Chewy hooks to the deploy flow
    task :add_default_hooks do
      after 'deploy:updated', 'deploy:chewy:rebuild'
    end

    # Default Chewy rake tasks
    desc 'Destroy, recreate and import data to all or specified (pass with [one,two]) indexes'
    task :reset do |_task, args|
      indexes = args.extras

      on roles fetch(:chewy_role) do
        within release_path do
          with rails_env: fetch(:chewy_env) do
            if indexes.any?
              execute :rake, "chewy:reset[#{indexes.join(',')}]"
            else
              # Simply chewy:reset / chewy:update for Chewy > 0.8.4
              execute :rake, 'chewy:reset:all'
            end
          end
        end
      end
    end

    desc 'Updates data to all or specified (passed with [one,two]) indexes'
    task :update do |_task, args|
      indexes = args.extras

      on roles fetch(:chewy_role) do
        within release_path do
          with rails_env: fetch(:chewy_env) do
            if indexes.any?
              execute :rake, "chewy:update[#{indexes.join(',')}]"
            else
              execute :rake, 'chewy:update:all'
            end
          end
        end
      end
    end

    # Smart rebuild of modified Chewy indexes
    desc 'Reset Chewy indexes if they have been added, changed or removed'
    task :rebuild do
      on roles fetch(:chewy_role) do
        if fetch(:chewy_skip)
          info 'Skipping task according to the deploy settings'
          exit 0
        end

        info "Checking Chewy directory (#{fetch(:chewy_path)})"

        chewy_path = File.join(release_path, fetch(:chewy_path))
        unless test("[ -d #{chewy_path} ]")
          error "Directory #{chewy_path} doesn't exist!"
          exit 1
        end

        if fetch(:chewy_conditionally_reset)
          if test('diff -v')
            info 'Running smart indexes reset...'
            invoke :'deploy:chewy:rebuilding'
          else
            error "Can't check the difference between Chewy indexes - install 'diff' tool first!"
            exit 1
          end
        else
          info 'Running chewy:reset:all'
          invoke :'deploy:chewy:reset:all'
        end
      end
    end

    desc 'Runs smart Chewy indexes rebuilding (only for changed files)'
    task :rebuilding do
      on roles fetch(:chewy_role) do
        if fetch(:chewy_skip)
          info 'Skipping task according to the deploy settings'
          exit 0
        end

        chewy_path = fetch(:chewy_path)
        info "Checking changes in #{chewy_path}"

        chewy_release_path = File.join(release_path, chewy_path)
        chewy_current_path = File.join(current_path, chewy_path)

        # -q, --brief                     report only when files differ
        # -E, --ignore-tab-expansion      ignore changes due to tab expansion
        # -Z, --ignore-trailing-space     ignore white space at line end
        # -B, --ignore-blank-lines        ignore changes where lines are all blank
        #
        diff_args = "-qZEB #{chewy_release_path} #{chewy_current_path}"
        indexes_diff = capture :diff, diff_args, raise_on_non_zero_exit: false
        changes = ::CapistranoChewy::DiffParser.parse(indexes_diff, chewy_current_path, chewy_release_path)

        # If diff is empty then indices have not changed
        if changes.empty?
          info 'Skipping `deploy:chewy:rebuilding` (nothing changed in the Chewy path)'
        else
          within release_path do
            with rails_env: fetch(:chewy_env) do
              # Reset indexes that were changed or added
              indexes_to_reset = changes.changed.concat(changes.added)

              if indexes_to_reset.any?
                indexes = indexes_to_reset.map { |file| File.basename(file).gsub('_index.rb', '') }.join(',')

                info "Modified or new indexes: #{indexes}"
                execute :rake, "chewy:reset[#{indexes}]"
              end

              # TODO: destroy removed indexes?
            end
          end
        end
      end
    end
  end
end
