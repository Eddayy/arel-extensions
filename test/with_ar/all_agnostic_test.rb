require 'helper'
require 'date'

module ArelExtensions
  module WthAr

    class ListTest < Minitest::Test
      require 'minitest/pride'
      def connect_db
        ActiveRecord::Base.configurations = YAML.load_file('test/database.yml')
        if ENV['DB'] == 'oracle' && ((defined?(RUBY_ENGINE) && RUBY_ENGINE == "rbx") || (RUBY_PLATFORM == 'java')) # not supported
          @env_db = (RUBY_PLATFORM == 'java' ? "jdbc-sqlite" : 'sqlite')
          skip "Platform not supported"
        else
          @env_db = ENV['DB']
        end
        ActiveRecord::Base.establish_connection(@env_db.try(:to_sym) || (RUBY_PLATFORM == 'java' ? :"jdbc-sqlite" : :sqlite))
        ActiveRecord::Base.default_timezone = :utc
        @cnx = ActiveRecord::Base.connection
        $sqlite = @cnx.adapter_name =~ /sqlite/i
        $load_extension_disabled ||= false
        csf = CommonSqlFunctions.new(@cnx)
        csf.add_sql_functions(@env_db)
      end

      def setup_db
        @cnx.drop_table(:user_tests) rescue nil 
        @cnx.create_table :user_tests do |t|
          t.column :age, :integer
          t.column :name, :string
          t.column :comments, :text
          t.column :created_at, :date
          t.column :updated_at, :datetime
          t.column :duration, :time
          t.column :score, :decimal, :precision => 20, :scale => 10
        end
        @cnx.drop_table(:product_tests) rescue nil
        @cnx.create_table :product_tests do |t|
          t.column :price, :decimal, :precision => 20, :scale => 10
        end
      end

      class User < ActiveRecord::Base
        self.table_name = 'user_tests'
      end
      class Product < ActiveRecord::Base
        self.table_name = 'product_tests'
      end

      def setup
        d = Date.new(2016, 5, 23)
        connect_db
        setup_db
        u = User.create :age => 5, :name => "Lucas", :created_at => d, :score => 20.16, :updated_at => Time.utc(2014, 3, 3, 12, 42, 0)
        @lucas = User.where(:id => u.id)
        u = User.create :age => 15, :name => "Sophie", :created_at => d, :score => 20.16
        @sophie = User.where(:id => u.id)
        u = User.create :age => 20, :name => "Camille", :created_at => d, :score => -20.16
        @camille = User.where(:id => u.id)
        u = User.create :age => 21, :name => "Arthur", :created_at => d, :score => 65.62, :comments => 'arrêté'
        @arthur = User.where(:id => u.id)
        u = User.create :age => 23, :name => "Myung", :created_at => d, :score => 20.16, :comments => ' '
        @myung = User.where(:id => u.id)
        u = User.create :age => 25, :name => "Laure", :created_at => d, :score => 20.16, :duration => Time.utc(2001, 1, 1, 12, 42, 21),:updated_at => Time.utc(2014, 3, 3, 12, 42, 0)
        @laure = User.where(:id => u.id)
        u = User.create :age => nil, :name => "Test", :created_at => d, :score => 1.62
        @test = User.where(:id => u.id)
        u = User.create :age => -42, :name => "Negatif", :comments => '1,22,3,42,2', :created_at => d, :updated_at => d.to_time, :score => 0.17
        @neg = User.where(:id => u.id)
        

        @age = User.arel_table[:age]
        @name = User.arel_table[:name]
        @score = User.arel_table[:score]
        @created_at = User.arel_table[:created_at]
        @updated_at = User.arel_table[:updated_at]
        @comments = User.arel_table[:comments]
        @duration = User.arel_table[:duration]
        @price = Product.arel_table[:price]
        @not_in_table = User.arel_table[:not_in_table]
        
        @ut = User.arel_table
        @pt = Product.arel_table
      end

      def teardown
        @cnx.drop_table(:user_tests)
        @cnx.drop_table(:product_tests)
      end

      def t(scope, node)
        scope.select(node.as('res')).first.res
      end

      # Math Functions
      def test_classical_arel
        assert_in_epsilon 42.16, t(@laure, @score + 22), 0.01
      end

      def test_abs
        assert_equal 42, t(@neg, @age.abs)
        assert_equal 20.16, t(@camille, @score.abs)
        assert_equal 14, t(@laure, (@age - 39).abs)
        assert_equal 28, t(@laure, (@age - 39).abs + (@age - 39).abs)
      end

      def test_ceil
#        skip "Sqlite version can't load extension for ceil" if $sqlite && $load_extension_disabled
        assert_equal 2, t(@test, @score.ceil) # 1.62
        assert_equal(-20, t(@camille, @score.ceil)) # -20.16
        assert_equal(-20, t(@camille, (@score - 0.5).ceil)) # -20.16
        assert_equal 63, t(@arthur, @age.ceil + 42)
      end

      def test_floor
#        skip "Sqlite version can't load extension for floor" if $sqlite && $load_extension_disabled
        assert_equal 0, t(@neg, @score.floor)
        assert_equal 1, t(@test, @score.floor) # 1.62
        assert_equal(-9, t(@test, (@score - 10).floor)) # 1.62
        assert_equal 42, t(@arthur, @score.floor - 23)
      end

      def test_rand
        assert 42 != User.select(Arel.rand.as('res')).first.res
        assert 0 <= User.select(Arel.rand.abs.as('res')).first.res
        assert_equal 8, User.order(Arel.rand).limit(50).count
      end

      def test_round
        assert_equal 1, User.where(@age.round(0).eq(5.0)).count
        assert_equal 0, User.where(@age.round(-1).eq(6.0)).count
        assert_equal 66, t(@arthur, @score.round)
        assert_in_epsilon 67.6, t(@arthur, @score.round(1) + 2), 0.01
      end

      def test_sum
        if @env_db == 'mssql'
          skip "SQL Server forces order?" # TODO
          assert_equal 68, User.select((@age.sum + 1).as("res"), User.arel_table[:id].sum).take(50).reorder(@age).first.res
          assert_equal 134, User.reorder(nil).select((@age.sum + @age.sum).as("res"), User.arel_table[:id].sum).take(50).first.res
          assert_equal 201, User.reorder(nil).select(((@age * 3).sum).as("res"), User.arel_table[:id].sum).take(50).first.res
          assert_equal 4009, User.reorder(nil).select(((@age * @age).sum).as("res"), User.arel_table[:id].sum).take(50).first.res
        else
          assert_equal 68, User.select((@age.sum + 1).as("res")).take(50).first.res
          assert_equal 134, User.select((@age.sum + @age.sum).as("res")).take(50).first.res
          assert_equal 201, User.select(((@age * 3).sum).as("res")).take(50).first.res
          assert_equal 4009, User.select(((@age * @age).sum).as("res")).take(50).first.res
        end
      end

      # String Functions
      def test_concat
		assert_equal 'Camille Camille', t(@camille, @name + ' ' + @name)
		assert_equal 'Laure 2', t(@laure, @name + ' ' + 2)
		assert_equal 'Test Laure', t(@laure, Arel::Nodes.build_quoted('Test ') + @name)
		skip "TODO: find a way... to do group_concat/listagg in SQL Server" if @env_db == 'mssql'
		if @env_db == 'postgresql'
			assert_equal "Lucas Sophie", t(User.reorder(nil).from(User.select(:name).where(:name => ['Lucas', 'Sophie']).reorder(:name).as('user_tests')), @name.group_concat(' '))                    
			assert_equal "Lucas,Sophie", t(User.reorder(nil).from(User.select(:name).where(:name => ['Lucas', 'Sophie']).reorder(:name).as('user_tests')), @name.group_concat(','))          
			assert_equal "Lucas Sophie", t(User.reorder(nil).from(User.select(:name).where(:name => ['Lucas', 'Sophie']).reorder(:name).as('user_tests')), @name.group_concat)
		else
			assert_equal "Lucas Sophie", t(User.where(:name => ['Lucas', 'Sophie']).reorder(:name), @name.group_concat(' '))
			assert_equal "Lucas,Sophie", t(User.where(:name => ['Lucas', 'Sophie']).reorder(:name), @name.group_concat(','))          
			if @env_db == 'oracle'
				assert_equal "LucasSophie", t(User.where(:name => ['Lucas', 'Sophie']).reorder(:name), @name.group_concat)
			else
				assert_equal "Lucas,Sophie", t(User.where(:name => ['Lucas', 'Sophie']).reorder(:name), @name.group_concat)
			end
		end
      end

      def test_length
        assert_equal 7, t(@camille, @name.length)
        assert_equal 7, t(@camille, @name.length.round.abs)
        assert_equal 42, t(@laure, @name.length + 37)
      end

      def test_locate
        skip "Sqlite version can't load extension for locate" if $sqlite && $load_extension_disabled
        assert_equal 1, t(@camille, @name.locate("C"))
        assert_equal 0, t(@lucas, @name.locate("z"))
        assert_equal 5, t(@lucas, @name.locate("s"))
      end

      def test_substring
        assert_equal 'C', t(@camille, @name.substring(1, 1))
        if @env_db == 'oracle'
          assert_nil(t(@lucas, @name.substring(42)))
        else
          assert_equal('', t(@lucas, @name.substring(42)))
        end
        assert_equal 'Lu', t(@lucas, @name.substring(1,2))

        assert_equal 'C', t(@camille, @name[0, 1])
        assert_equal 'C', t(@camille, @name[0])
        if @env_db == 'oracle'
          assert_nil(t(@lucas, @name[42]))
        else
          assert_equal('', t(@lucas, @name[42]))
        end
        assert_equal 'Lu', t(@lucas, @name[0,2])
        assert_equal 'Lu', t(@lucas, @name[0..1])
        
        #substring should accept string function
        assert_equal 'Ce', t(@camille, @name.substring(1, 1).concat('e'))
        assert_equal 'Ce', t(@camille, @name.substring(1, 1)+'e')
      end

      def test_find_in_set
        skip "Sqlite version can't load extension for find_in_set" if $sqlite && $load_extension_disabled
        skip "SQL Server does not know about FIND_IN_SET" if @env_db == 'mssql'
        assert_equal 5, t(@neg, @comments & 2)
        assert_equal 0, t(@neg, @comments & 6) # not found
      end

      def test_string_comparators
        #skip "Oracle can't use math operators to compare strings" if @env_db == 'oracle' # use GREATEST ?
        skip "SQL Server can't use math operators to compare strings" if @env_db == 'mssql' # use GREATEST ?
        if @env_db == 'postgresql' # may return real boolean
          assert t(@neg, @name >= 'Mest') == true || t(@neg, @name >= 'Mest') == 't' # depends of ar version
          assert t(@neg, @name <= (@name + 'Z')) == true || t(@neg, @name <= (@name + 'Z')) == 't'
        elsif @env_db == 'oracle' 
		  assert_equal 1, t(@neg, ArelExtensions::Nodes::Case.new.when(@name >= 'Mest').then(1).else(0))
          assert_equal 1, t(@neg, ArelExtensions::Nodes::Case.new.when(@name <= (@name + 'Z')).then(1).else(0))
          assert_equal 1, t(@neg, ArelExtensions::Nodes::Case.new.when(@name > 'Mest').then(1).else(0))
          assert_equal 1, t(@neg, ArelExtensions::Nodes::Case.new.when(@name < (@name + 'Z')).then(1).else(0))
        else
          assert_equal 1, t(@neg, @name >= 'Mest')
          assert_equal 1, t(@neg, @name <= (@name + 'Z'))
          assert_equal 1, t(@neg, @name > 'Mest')
          assert_equal 1, t(@neg, @name < (@name + 'Z'))
        end
      end
      
      def test_compare_on_date_time_types 
		skip "Sqlite can't compare time" if $sqlite 		
		skip "Oracle can't compare time" if @env_db == 'oracle'
		#@created_at == 2016-05-23
        assert_includes [true,'t',1], t(@laure, ArelExtensions::Nodes::Case.new.when(@created_at >= '2014-01-01').then(1).else(0))
        assert_includes [false,'f',0], t(@laure, ArelExtensions::Nodes::Case.new.when(@created_at >= '2018-01-01').then(1).else(0))
        #@updated_at == 2014-03-03 12:42:00
	    assert_includes [true,'t',1], t(@laure, ArelExtensions::Nodes::Case.new.when(@updated_at >= '2014-03-03 10:10:10').then(1).else(0))
	    assert_includes [false,'f',0], t(@laure, ArelExtensions::Nodes::Case.new.when(@updated_at >= '2014-03-03 13:10:10').then(1).else(0))
	    #@duration == 12:42:21
	    #puts @laure.select(ArelExtensions::Nodes::Case.new.when(@duration >= '10:10:10').then(1).else(0)).to_sql
	    #puts @laure.select(ArelExtensions::Nodes::Case.new.when(@duration >= '14:10:10').then(1).else(0)).to_sql
	    assert_includes [true,'t',1], t(@laure, ArelExtensions::Nodes::Case.new.when(@duration >= '10:10:10').then(1).else(0))
	    assert_includes [false,'f',0], t(@laure, ArelExtensions::Nodes::Case.new.when(@duration >= '14:10:10').then(1).else(0))
      end
      

      def test_regexp_not_regexp
        skip "Sqlite version can't load extension for regexp" if $sqlite && $load_extension_disabled
        skip "SQL Server does not know about REGEXP without extensions" if @env_db == 'mssql'
        assert_equal 1, User.where(@name =~ '^M').count
        assert_equal 6, User.where(@name !~ '^L').count
        assert_equal 1, User.where(@name =~ /^M/).count
        assert_equal 6, User.where(@name !~ /^L/).count
      end

      def test_imatches
		#puts User.where(@name.imatches('m%')).to_sql
        assert_equal 1, User.where(@name.imatches('m%')).count
        assert_equal 4, User.where(@name.imatches_any(['L%', '%e'])).count
        assert_equal 6, User.where(@name.idoes_not_match('L%')).count
      end

      def test_replace
        assert_equal "LucaX", t(@lucas, @name.replace("s", "X"))
        assert_equal "replace", t(@lucas, @name.replace(@name, "replace"))
      end

      def test_replace_once
        skip "TODO"
#        skip "Sqlite version can't load extension for locate" if $sqlite && $load_extension_disabled
        assert_equal "LuCas", t(@lucas, @name.substring(1, @name.locate('c') - 1) + 'C' + @name.substring(@name.locate('c') + 1, @name.length))
      end

      def test_soundex
        skip "Sqlite version can't load extension for soundex" if $sqlite && $load_extension_disabled
        skip "PostgreSql version can't load extension for soundex" if @env_db == 'postgresql'
        assert_equal "C540", t(@camille, @name.soundex)
        assert_equal 8, User.where(@name.soundex.eq(@name.soundex)).count
        assert_equal 8, User.where(@name.soundex == @name.soundex).count
      end

      def test_change_case
        assert_equal "myung", t(@myung, @name.downcase)
        assert_equal "MYUNG", t(@myung, @name.upcase)
        assert_equal "myung", t(@myung, @name.upcase.downcase)
      end

      def test_trim
        assert_equal "Myung", t(@myung, @name.trim)
        assert_equal "Myung", t(@myung, @name.trim.ltrim.rtrim)
        assert_equal "Myun", t(@myung, @name.rtrim("g"))
        assert_equal "yung", t(@myung, @name.ltrim("M"))
        assert_equal "yung", t(@myung, (@name + "M").trim("M"))
        skip "Oracle does not accept multi char trim" if @env_db == 'oracle'
        assert_equal "", t(@myung, @name.rtrim(@name))
      end

      def test_blank
        if @env_db == 'postgresql'
          assert_includes [false, 'f'], t(@myung, @name.blank) # depends of adapter
          assert_includes [true, 't'], t(@myung, @name.not_blank) # depends of adapter
          assert_includes [true, 't'], t(@myung, @comments.blank)
          assert_includes [false, 'f'], t(@myung, @comments.not_blank)
        end
        assert_equal 0, @myung.where(@name.blank).count
        assert_equal 1, @myung.where(@name.not_blank).count
        assert_equal 1, @myung.where(@comments.blank).count
        assert_equal 0, @neg.where(@comments.blank).count
        assert_equal 1, @neg.where(@comments.not_blank).count
        assert_equal 0, @myung.where(@comments.not_blank).count
        assert_equal 'false', t(@myung, @name.blank.then('true', 'false'))
        assert_equal 'true', t(@myung, @name.not_blank.then('true', 'false'))
        assert_equal 'true', t(@myung, @comments.blank.then('true', 'false'))
        assert_equal 'false', t(@myung, @comments.not_blank.then('true', 'false'))
        assert_equal 'false', t(@neg, @comments.blank.then('true', 'false'))
        assert_equal 'true', t(@neg, @comments.not_blank.then('true', 'false'))
      end

      def test_format
        assert_equal '2016-05-23', t(@lucas, @created_at.format('%Y-%m-%d'))
        skip "SQL Server does not accept any format" if @env_db == 'mssql'
        assert_equal '2014/03/03 12:42:00', t(@lucas, @updated_at.format('%Y/%m/%d %H:%M:%S'))
      end

      def test_coalesce
        assert_equal 'Camille concat', t(@camille, @name.coalesce(nil, "default") + ' concat')

        assert_equal ' ', t(@myung, @comments.coalesce("Myung").coalesce('ignored'))
        assert_equal 'Laure', t(@laure, @comments.coalesce("Laure"))
        if @env_db == 'oracle'
          assert_nil t(@laure, @comments.coalesce(""))
        else
          assert_equal('', t(@laure, @comments.coalesce("")))
        end

        if @env_db == 'postgresql'
          assert_equal 100, t(@test, @age.coalesce(100))
          assert_equal "Camille", t(@camille, @name.coalesce(nil, "default"))
          assert_equal 20, t(@test, @age.coalesce(nil, 20))
        else
          assert_equal "Camille", t(@camille, @name.coalesce(nil, '20'))
          assert_equal 20, t(@test, @age.coalesce(nil, 20))
        end
      end

      # Comparators
      def test_number_comparator
        assert_equal 2, User.where(@age < 6).count
        assert_equal 2, User.where(@age <= 10).count
        assert_equal 3, User.where(@age > 20).count
        assert_equal 4, User.where(@age >= 20).count
        assert_equal 1, User.where(@age > 5).where(@age < 20).count
      end

      def test_date_comparator
        d = Date.new(2016, 5, 23)
        assert_equal 0, User.where(@created_at < d).count
        assert_equal 8, User.where(@created_at >= d).count
      end

      def test_date_duration
        #Year
        assert_equal 2016, t(@lucas, @created_at.year).to_i        
        assert_equal 0, User.where(@created_at.year.eq("2012")).count
        #Month
        assert_equal 5, t(@camille, @created_at.month).to_i
        assert_equal 8, User.where(@created_at.month.eq("05")).count
        #Week
        assert_equal(@env_db == 'mssql' ? 22 : 21, t(@arthur, @created_at.week).to_i)
        assert_equal 8, User.where(@created_at.month.eq("05")).count
        #Day
        assert_equal 23, t(@laure, @created_at.day).to_i
        assert_equal 0, User.where(@created_at.day.eq("05")).count

        skip "manage DATE" if @env_db == 'oracle'
        #Hour
        assert_equal 0, t(@laure, @created_at.hour).to_i
        assert_equal 12, t(@lucas, @updated_at.hour).to_i
        #Minute
        assert_equal 0, t(@laure, @created_at.minute).to_i
        assert_equal 42, t(@lucas, @updated_at.minute).to_i
        #Second
        assert_equal 0, t(@laure, @created_at.second).to_i
        assert_equal 0, t(@lucas, @updated_at.second).to_i
      end

      def test_datetime_diff
        assert_equal 0, t(@lucas, @updated_at - Time.utc(2014, 3, 3, 12, 42)).to_i
        if @env_db == 'oracle' && Arel::VERSION.to_i > 6 # in rails 5, result is multiplied by 24*60*60 = 86400...
          assert_equal 42 * 86400, t(@lucas, @updated_at - Time.utc(2014, 3, 3, 12, 41, 18)).to_i
          assert_equal(-3600 * 86400, t(@lucas, @updated_at - Time.utc(2014, 3, 3, 13, 42)).to_i)          
        else
          assert_equal 42, t(@lucas, @updated_at - Time.utc(2014, 3, 3, 12, 41, 18)).to_i
          assert_equal(-3600, t(@lucas, @updated_at - Time.utc(2014, 3, 3, 13, 42)).to_i)
          if @env_db == 'mssql' || @env_db == 'oracle' # can't select booleans
            assert_equal 0, @lucas.where((@updated_at - Time.utc(2014, 3, 3, 12, 41, 18)) < -1).count
          else
            assert_includes [nil, 0, 'f', false], t(@lucas, (@updated_at - Time.utc(2014, 3, 3, 12, 41, 18)) < -1)
          end
          if @env_db == 'mysql'
			date1 = Date.new(2016, 5, 23)
			durPos = 10.years
			durNeg = -10.years
			date2 = date1 + durPos
			date3 = date1 - durPos
			# Pull Request #5 tests
			assert_includes [date2,"2026-05-23"], t(@test,(@created_at + durPos))
			assert_includes [date3,"2006-05-23"], t(@test,(@created_at + durNeg))
			# we test with the ruby object or the string because some adapters don't return an object Date
          end
        end
      end

      # TODO; cast types
      def test_cast_types
		assert_equal "5", t(@lucas, @age.cast(:string))
		if @env_db == 'mysql' || @env_db == 'postgresql' || @env_db == 'oracle'			
			assert_equal 1, t(@laure,ArelExtensions::Nodes::Case.new.when(@duration.cast(:time).cast(:string).eq("12:42:21")).then(1).else(0))
			assert_equal 1, t(@laure,ArelExtensions::Nodes::Case.new.when(@duration.cast(:time).eq("12:42:21")).then(1).else(0))
		end
      end

      def test_is_null	
		#puts User.where(@age.is_null).select(@name).to_sql
        assert_equal "Test", User.where(@age.is_null).select(@name).first.name
      end

      def test_math_plus
        d = Date.new(1997, 6, 15)
        #Concat String
        assert_equal "SophiePhan", t(@sophie, @name + "Phan")
        assert_equal "Sophie2", t(@sophie, @name + 2)
        assert_equal "Sophie1997-06-15", t(@sophie, @name + d)
        assert_equal "Sophie15", t(@sophie, @name + @age)
        assert_equal "SophieSophie", t(@sophie, @name + @name)
        #FIXME: should work as expected in Oracle
        assert_equal "Sophie2016-05-23", t(@sophie, @name + @created_at) unless @env_db == 'oracle'
        #concat Integer
        assert_equal 1, User.where((@age + 10).eq(33)).count
        assert_equal 1, User.where((@age + "1").eq(6)).count
        assert_equal 1, User.where((@age + @age).eq(10)).count
        #concat Date
    #    puts((User.arel_table[:created_at] + 1).as("res").to_sql.inspect)
        assert_equal "2016-05-24", t(@myung, @created_at + 1).to_date.to_s
        assert_equal "2016-05-25", t(@myung, @created_at + 2.day).to_date.to_s
      end


      def test_math_minus
        d = Date.new(2016, 5, 20)
        #Datediff
        assert_equal 8, User.where((@created_at - @created_at).eq(0)).count
        assert_equal 3, @laure.select((@created_at - d).as("res")).first.res.abs.to_i
        #Substraction
        assert_equal 0, User.where((@age - 10).eq(50)).count
        assert_equal 0, User.where((@age - "10").eq(50)).count
        # assert_equal 0, User.where((@age - 9.5).eq(50.5)).count # should work: TODO
        assert_equal 0, User.where((@age - "9.5").eq(50.5)).count
      end

      def test_wday
        d = Date.new(2016, 6, 26)
        assert_equal(@env_db == 'oracle' || @env_db == 'mssql' ? 2 : 1, t(@myung, @created_at.wday).to_i) # monday
        assert_equal 0, User.select(d.wday).as("res").first.to_i
      end

      # Boolean functions
      def test_boolean_functions
        assert_equal 1, @laure.where(
          (@score.round > 19).⋀(@score.round < 21).⋁(@score.round(1) >= 20.1)
        ).count
      end
      
      # Union operator
      def test_union_operator      
        assert_equal 3, User.find_by_sql((@ut.project(@age).where(@age.gt(22)) + @ut.project(@age).where(@age.lt(0))).to_sql).length
		assert_equal 2, User.find_by_sql((@ut.project(@age).where(@age.eq(20)) + @ut.project(@age).where(@age.eq(20)) + @ut.project(@age).where(@age.eq(21))).to_sql).length
        assert_equal 3, User.select('*').from((@ut.project(@age).where(@age.gt(22)) + @ut.project(@age).where(@age.lt(0))).as('my_union')).length
        assert_equal 3, User.select('*').from((@ut.project(@age).where(@age.eq(20)) + @ut.project(@age).where(@age.eq(23)) + @ut.project(@age).where(@age.eq(21))).as('my_union')).length
        assert_equal 2, User.select('*').from((@ut.project(@age).where(@age.eq(20)) + @ut.project(@age).where(@age.eq(20)) + @ut.project(@age).where(@age.eq(21))).as('my_union')).length
        
        assert_equal 3, User.find_by_sql((@ut.project(@age).where(@age.gt(22)).union_all(@ut.project(@age).where(@age.lt(0)))).to_sql).length
		assert_equal 3, User.find_by_sql((@ut.project(@age).where(@age.eq(20)).union_all(@ut.project(@age).where(@age.eq(20))).union_all(@ut.project(@age).where(@age.eq(21)))).to_sql).length
        assert_equal 3, User.select('*').from((@ut.project(@age).where(@age.gt(22)).union_all(@ut.project(@age).where(@age.lt(0)))).as('my_union')).length
        assert_equal 3, User.select('*').from((@ut.project(@age).where(@age.eq(20)).union_all(@ut.project(@age).where(@age.eq(23))).union_all(@ut.project(@age).where(@age.eq(21)))).as('my_union')).length
        assert_equal 3, User.select('*').from((@ut.project(@age).where(@age.eq(20)).union_all(@ut.project(@age).where(@age.eq(20))).union_all(@ut.project(@age).where(@age.eq(21)))).as('my_union')).length
      end

	  # Case clause
	  def test_case
	    assert_equal 4, User.find_by_sql(@ut.project(@score.when(20.16).then(1).else(0).as('score_bin')).to_sql).sum(&:score_bin)
	  end
	  
	  def test_format_numbers
		skip "Not yet implemented" if @env_db != 'mysql' && @env_db != 'postgresql'
		#score of Arthur = 65.62
		assert_equal "AZERTY65,62" , t(@arthur, @score.format_number("AZERTY%.2f","fr_FR"))
		assert_equal "65,62AZERTY" , t(@arthur, @score.format_number("%.2fAZERTY","fr_FR"))
		assert_equal "$ 65.62 €" , t(@arthur, @score.format_number("$ %.2f €","en_EN"))		
		assert_equal "$ 0065,62 €" , t(@arthur, @score.format_number("$ %07.2f €","fr_FR"))
		assert_equal "$ 65,62   €" , t(@arthur, @score.format_number("$ %-07.2f €","fr_FR"))
		assert_equal "$ 65,62   €" , t(@arthur, @score.format_number("$ %-7.2f €","fr_FR"))
		assert_equal "$   65,62 €" , t(@arthur, @score.format_number("$ % 7.2f €","fr_FR"))
		assert_equal "$    65,6 €" , t(@arthur, @score.format_number("$ % 7.1f €","fr_FR"))
		assert_equal "$  +65,62 €" , t(@arthur, @score.format_number("$ % +7.2f €","fr_FR"))		
		assert_equal "$ +065,62 €" , t(@arthur, @score.format_number("$ %0+7.2f €","fr_FR"))	
		assert_equal "$ 6,56e1 €" , t(@arthur, @score.format_number("$ %.2e €","fr_FR"))			
		assert_equal "$ 6,56E1 €" , t(@arthur, @score.format_number("$ %.2E €","fr_FR"))			
		assert_equal "$ 6,562E1 €" , t(@arthur, @score.format_number("$ %.3E €","fr_FR"))	
		assert_equal "Wrong Format" , t(@arthur, @score.format_number("$ %...234.6F €","fr_FR"))
	  end
	  
	  def test_accent_insensitive
		skip "SQLite is natively Case Insensitive and Accent Sensitive" if $sqlite
		skip "Not finished" if @env_db == 'mysql'
		# actual comments value: "arrêté"		
		#AI & CI	
		if !['postgresql'].include?(@env_db) # Extension unaccent required on PG
			assert_equal "1", t(@arthur,ArelExtensions::Nodes::Case.new.when(@comments.ai_imatches("arrêté")).then("1").else("0"))
			assert_equal "1", t(@arthur,ArelExtensions::Nodes::Case.new.when(@comments.ai_imatches("arrete")).then("1").else("0"))		  		  
			assert_equal "1", t(@arthur,ArelExtensions::Nodes::Case.new.when(@comments.ai_imatches("àrrétè")).then("1").else("0"))		  		  
			assert_equal "0", t(@arthur,ArelExtensions::Nodes::Case.new.when(@comments.ai_imatches("arretez")).then("1").else("0"))		  
			assert_equal "1", t(@arthur,ArelExtensions::Nodes::Case.new.when(@comments.ai_imatches("Arrete")).then("1").else("0"))
			assert_equal "1", t(@arthur,ArelExtensions::Nodes::Case.new.when(@comments.ai_imatches("Arrêté")).then("1").else("0"))
			#AI & CS
			assert_equal "1", t(@arthur,ArelExtensions::Nodes::Case.new.when(@comments.ai_matches("arrêté")).then("1").else("0"))
			assert_equal "1", t(@arthur,ArelExtensions::Nodes::Case.new.when(@comments.ai_matches("arrete")).then("1").else("0"))		  		  
			assert_equal "1", t(@arthur,ArelExtensions::Nodes::Case.new.when(@comments.ai_matches("àrrétè")).then("1").else("0"))		  		  
			assert_equal "0", t(@arthur,ArelExtensions::Nodes::Case.new.when(@comments.ai_matches("arretez")).then("1").else("0"))		  
			if !['oracle','postgresql','mysql'].include?(@env_db) # AI => CI
				assert_equal "0", t(@arthur,ArelExtensions::Nodes::Case.new.when(@comments.ai_matches("Arrete")).then("1").else("0"))
				assert_equal "0", t(@arthur,ArelExtensions::Nodes::Case.new.when(@comments.ai_matches("Arrêté")).then("1").else("0"))
			end			
		end
		#AS & CI
		assert_equal "1", t(@arthur,ArelExtensions::Nodes::Case.new.when(@comments.imatches("arrêté")).then("1").else("0"))
		if !['mysql'].include?(@env_db) # CI => AI in utf8 (AI not possible in latin1)
			assert_equal "0", t(@arthur,ArelExtensions::Nodes::Case.new.when(@comments.imatches("arrete")).then("1").else("0"))		  		  
			assert_equal "0", t(@arthur,ArelExtensions::Nodes::Case.new.when(@comments.imatches("àrrétè")).then("1").else("0"))		  		  
		end		  
		assert_equal "0", t(@arthur,ArelExtensions::Nodes::Case.new.when(@comments.imatches("arretez")).then("1").else("0"))		  
		if !['mysql'].include?(@env_db) # CI => AI in utf8 (AI not possible in latin1)
			assert_equal "0", t(@arthur,ArelExtensions::Nodes::Case.new.when(@comments.imatches("Arrete")).then("1").else("0"))
		end
		assert_equal "1", t(@arthur,ArelExtensions::Nodes::Case.new.when(@comments.imatches("Arrêté")).then("1").else("0"))
		#AS & CS
		assert_equal "1", t(@arthur,ArelExtensions::Nodes::Case.new.when(@comments.smatches("arrêté")).then("1").else("0"))
		assert_equal "0", t(@arthur,ArelExtensions::Nodes::Case.new.when(@comments.smatches("arrete")).then("1").else("0"))		  		  
		assert_equal "0", t(@arthur,ArelExtensions::Nodes::Case.new.when(@comments.smatches("àrrétè")).then("1").else("0"))		  		  
		assert_equal "0", t(@arthur,ArelExtensions::Nodes::Case.new.when(@comments.smatches("arretez")).then("1").else("0"))		  
		assert_equal "0", t(@arthur,ArelExtensions::Nodes::Case.new.when(@comments.smatches("Arrete")).then("1").else("0"))
		assert_equal "0", t(@arthur,ArelExtensions::Nodes::Case.new.when(@comments.smatches("Arrêté")).then("1").else("0"))  
	  end
	  
	  def test_subquery_with_order	  
		assert_equal 8, User.where(:name => User.select(:name).order(:name)).count 
		assert_equal 8, User.where(@ut[:name].in(@ut.project(@ut[:name]).order(@ut[:name]))).count 
		if !['mysql'].include?(@env_db)	# MySql can't have limit in IN subquery	
			assert_equal 2, User.where(:name => User.select(:name).order(:name).limit(2)).count 
			#assert_equal 6, User.where(:name => User.select(:name).order(:name).offset(2)).count 
		end
	  end
	 
    end
  end
end
