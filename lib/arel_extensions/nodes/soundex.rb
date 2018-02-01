module ArelExtensions
	module Nodes
		class Soundex < Function					
			@@return_type = :string
				
			def ==(other)
				Arel::Nodes::Equality.new self, Arel::Nodes.build_quoted(other, self)
			end

			def !=(other)
				Arel::Nodes::NotEqual.new self, Arel::Nodes.build_quoted(other, self)
			end
		end
	end
end
