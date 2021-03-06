module ActiveRecord
  module Associations
    module ClassMethods
      def inherited_attribute(name, parent)
        name = name.to_s
        class_eval "def #{name}; (v = read_attribute(:#{name})).nil? ? #{parent.to_s}.#{name} : v; end"
        class_eval "alias_method :#{name}?, :#{name}" 
      end
      
      # generates a method like "share_mobile_phone_with(person)"
      def share_with(attribute)
        class_eval \
          "
          def share_#{attribute}_with(person)
            return :admin if self.is_a?(Family) and not self.visible?
            return :admin if self.is_a?(Person) and not (self.visible? and self.family.visible?)
            return :admin if self == person or person.admin?(:view_hidden_properties)
            return :admin if self.is_a?(Family) and self == person.family
            return :admin if self.is_a?(Person) and self.family == person.family
            return true if share_#{attribute}
          end
          "
      end
    end
  end
end

