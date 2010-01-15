module Neo4j


  # Represents a node in the Neo4j space.
  # 
  # Is a wrapper around a Java Neo4j node (org.neo4j.api.core.Node)
  # The following methods are delegated to the Java Neo4j Node:
  #   []=, [], property?, props, update, neo_id, rels, rel?, to_param
  #   rel, del, list?, list, lists, print, add_rel, outgoing, incoming,
  #   next, prev, next=, prev=, head
  #
  #
  # Those methods are defined in the mixins Neo4j::JavaPropertyMixin, Neo4j::JavaNodeMixin, Neo4j::JavaListMixin.
  #
  module NodeMixin
    extend Forwardable

    def_delegators :@_java_node, :[]=, :[], :property?, :props, :update, :neo_id, :rels, :rel?, :to_param,
                   :rel, :del, :list?, :list, :lists, :print, :print_sub, :add_rel, :outgoing, :incoming,
                   :add_list_item_methods, :next, :prev, :next=, :prev=, :head # used for has_list, defined in Neo4j::JavaListMixin


    # --------------------------------------------------------------------------
    # Initialization methods
    #


    # Initialize the the neo node for this instance.
    # Will create a new transaction if one is not already running.
    # 
    # Does
    # * sets the neo property '_classname' to self.class.to_s
    # * creates a neo node java object (in @_java_node)
    # * calls init_node if that is defined in the current class.
    #
    # If you want to provide your own initialize method you should instead implement the
    # method init_node method.
    #
    # Example:
    #   class MyNode
    #     include Neo4j::NodeMixin
    #
    #     def init_node(name, age)
    #        self[:name] = name
    #        self[:age] = age
    #     end
    #   end
    #
    #   node = MyNode('jimmy', 23)
    #
    # The init_node is only called when the node is constructed the first, unlike te initialize method which is used both for
    # loading the node from the Neo4j database and creating the Ruby object.
    #
    # :api: public
    def initialize(*args)
      # was a neo java node provided ?
      if args.length == 1 and args[0].kind_of?(org.neo4j.api.core.Node)
        init_with_node(args[0])
      else
        init_without_node
        init_node(*args) if self.respond_to?(:init_node)
      end
      yield self if block_given?
      # must call super with no arguments so that chaining of the initialize method works
      super()
    end


    # Inits this node with the specified java neo node
    #
    # :api: private
    def init_with_node(java_node) # :nodoc:
      @_java_node = java_node
      java_node._wrapper=self
    end

    # Returns the org.neo4j.api.core.Node wrapped object
    def _java_node
      @_java_node
    end

    # Inits when no neo java node exists. Must create a new neo java node first.
    #
    # :api: private
    def init_without_node # :nodoc:
      @_java_node = Neo4j.create_node
      @_java_node._wrapper = self
      @_java_node[:_classname] = self.class.to_s
      Neo4j.event_handler.node_created(self)
    end


    # --------------------------------------------------------------------------
    # Property methods
    #


    # Creates a struct class containing all properties of this class.
    # This value object can be used from Ruby on Rails RESTful routing.
    #
    # ==== Example
    #
    # h = Person.value_object.new
    # h.name    # => nil
    # h.name='kalle'
    # h[:name]   # => 'kalle'
    #
    # ==== Returns
    # a value object struct
    #
    # :api: public
    def value_object
      vo = self.class.value_object.new
      vo._update(props)
      vo
    end


    # --------------------------------------------------------------------------
    # Equal and hash methods
    #

    def eql?(o)
      o.kind_of?(NodeMixin) && o._java_node == @_java_node
    end

    def ==(o)
      eql?(o)
    end

    def hash
      @_java_node.hashCode
    end


    # --------------------------------------------------------------------------
    # Update and Delete methods
    #


    # Specifies which relationships should be ignored when trying to cascade delete a node.
    # If a node does not have any relationships (except those specified here to ignore) it will be cascade deleted
    #
    def ignore_incoming_cascade_delete?(relationship) # :nodoc:
      # ignore relationship with property _cascade_delete_incoming
      relationship.property?(:_cascade_delete_incoming)
    end

    # Updates the index for this node.
    # This method will be automatically called when needed
    # (a property changed or a relationship was created/deleted)
    #
    # @api private
    def update_index # :nodoc:
      self.class.indexer.index(self)
    end

    # --------------------------------------------------------------------------
    # Relationship methods
    #

    # Returns a Neo4j::Relationships::NodeTraverser object for traversing nodes from and to this node.
    # The Neo4j::Relationships::NodeTraverser is an Enumerable that returns Neo4j::NodeMixin objects.
    #
    # ==== See Also
    # Neo4j::Relationships::NodeTraverser
    #
    # ==== Example
    #
    #   person_node.traverse.outgoing(:friends).each { ... }
    #   person_node.traverse.outgoing(:friends).raw(true).each { }
    #
    # The raw false parameter means that the ruby wrapper object will not be loaded, instead the raw Java Neo4j object will be used,
    # it might improve the performance.
    #
    # :api: public
    def traverse(*args)
      if args.empty?
        Neo4j::Relationships::NodeTraverser.new(self)
      else
        @_java_node.traverse(*args)
      end

    end


    # --------------------------------------------------------------------------
    # Private methods
    #

    # :api: private
    def _to_java_direction(dir) # :nodoc:
      case dir
        when :outgoing
          org.neo4j.api.core.Direction::OUTGOING
        when :incoming
          org.neo4j.api.core.Direction::INCOMING
        when :both
          org.neo4j.api.core.Direction::BOTH
        else
          raise "Unknown parameter: '#{dir}', only accept :outgoing, :incoming or :both"
      end
    end


    # --------------------------------------------------------------------------
    # Hooks
    #


    # Adds class methods in the ClassMethods module
    #
    def self.included(c) # :nodoc:
      # all subclasses share the same index, declared properties and index_updaters
      c.instance_eval do
        const_set(:ROOT_CLASS, self)
        const_set(:DECL_RELATIONSHIPS, {})
        const_set(:PROPERTIES_INFO, {})
      end unless c.const_defined?(:ROOT_CLASS)

      c.extend ClassMethods
    end


    # --------------------------------------------------------------------------
    # NodeMixin class methods
    #
    module ClassMethods

      #
      # Access to class constants.
      # These properties are shared by the class and its siblings.
      # For example that means that we can specify properties for a parent
      # class and the child classes will 'inherit' those properties.
      #

      # :api: private
      def root_class # :nodoc:
        self::ROOT_CLASS
      end

      def indexer # :nodoc:
        Indexer.instance(root_class)
      end


      # Contains information of all relationships, name, type, and multiplicity
      #
      # :api: private
      def decl_relationships # :nodoc:
        self::DECL_RELATIONSHIPS
      end

      # :api: private
      def properties_info # :nodoc:
        self::PROPERTIES_INFO
      end


      # ------------------------------------------------------------------------


      # Generates accessor method and sets configuration for Neo4j node properties.
      # The generated accessor is a simple wrapper around the #set_property and
      # #get_property methods.
      #
      # If a property is set to nil the property will be removed.
      #
      # ==== Configuration
      # By setting the :type configuration parameter to 'Object' makes
      # it possible to marshal any ruby object.
      #
      # If no type is provided the only the native Neo4j property types are allowed:
      # * TrueClass, FalseClass
      # * String
      # * Fixnum
      # * Float
      # * Boolean
      #
      # ==== Parameters
      # props<Array,Hash>:: a variable length arguments or a hash, see example below
      #
      # ==== Example
      #   class Baaz; end
      #
      #   class Foo
      #     include Neo4j::NodeMixin
      #     property :name, :city # can set several properties in one go
      #     property :bar, :type => Object # allow serialization of any ruby object
      #   end
      #
      #   f = Foo.new
      #   f.bar = Baaz.new
      #
      # :api: public
      def property(*props)
        if props.size == 2 and props[1].kind_of?(Hash)
          props[1].each_pair do |key, value|
            pname = props[0].to_sym
            properties_info[pname] ||= {}
            properties_info[pname][key] = value
          end
          props = props[0..0]
        end

        props.each do |prop|
          pname = prop.to_sym
          properties_info[pname] ||= {}
          properties_info[pname][:defined] = true

          define_method(pname) do
            self[pname]
          end

          name = (pname.to_s() +"=").to_sym
          define_method(name) do |value|
            self[pname] = value
          end
        end
      end

      # Returns true if the given property name should be marshalled.
      # All properties that has a type will be marshalled.
      #
      # ===== Example
      #   class Foo
      #     include Neo4j::NodeMixin
      #     property :name
      #     property :since, :type => Date
      #   end
      #   Foo.marshal?(:since) => true
      #   Foo.marshal?(:name) => false
      #
      # ==== Returns
      # true if the property will be marshalled, false otherwise
      #
      # :api: public
      def marshal?(prop_name)
        return false if properties_info[prop_name.to_sym].nil?
        return false if properties_info[prop_name.to_sym][:type].nil?
        return true
      end


      # Returns true if the given property name has been defined with the class
      # method property or properties.
      #
      # Notice that the node may have properties that has not been declared.
      # It is always possible to set an undeclared property on a node.
      #
      # ==== Returns
      # true or false
      #
      # :api: public
      def property?(prop_name)
        return false if properties_info[prop_name.to_sym].nil?
        properties_info[prop_name.to_sym][:defined] == true
      end


      # Creates a struct class containig all properties of this class.
      #
      # ==== Example
      #
      # h = Person.value_object.new
      # h.name    # => nil
      # h.name='kalle'
      # h[:name]   # => 'kalle'
      #
      # ==== Returns
      # Struct
      #
      # :api: public
      def value_object
        @value_class ||= create_value_class
      end

      # Index a property or a relationship.
      # If the rel_prop arg contains a '.' then it will index the relationship.
      # For example "friends.name" will index each node with property name in the relationship friends.
      # For example "name" will index the name property of this NodeMixin class.
      #
      # ==== Example
      #   class Person
      #     include Neo4j::NodeMixin
      #     property :name
      #     index :name
      #   end
      #
      # :api: public
      def index(*rel_type_props)
        if rel_type_props.size == 2 and rel_type_props[1].kind_of?(Hash)
          rel_type_props[1].each_pair do |key, value|
            idx = rel_type_props[0]
            indexer.field_infos[idx.to_sym][key] = value
          end
          rel_type_props = rel_type_props[0..0]
        end
        rel_type_props.each do |rel_type_prop|
          rel_name, prop = rel_type_prop.to_s.split('.')
          index_property(rel_name) if prop.nil?
          index_relationship(rel_name, prop) unless prop.nil?
        end
      end


      # Remove one or more specified indexes.
      # Those indexes will not be updated anymore, old indexes will still exist
      # until the update_index method is called.
      #
      # :api: public
      def remove_index(*keys)
        keys.each do |key|
          raise "Not implemented remove index on a relationship index" if key.to_s.include?('.')
          indexer.remove_index_on_property(key)
        end
      end


      # :api: private
      def index_property(prop) # :nodoc:
        indexer.add_index_on_property(prop)
      end


      # :api: private
      def index_relationship(rel_name, prop) # :nodoc:
        # find the trigger and updater classes and the rel_type of the given rel_name
        trigger_clazz = decl_relationships[rel_name.to_sym].clazz
        trigger_clazz ||= self # if not defined in a has_n

        updater_clazz = self

        dsl = decl_relationships[rel_name.to_sym]
        rel_type = dsl.type # this or the other node we index ?
        rel_type ||= rel_name # if not defined (in a has_n) use the same name as the rel_name

        if dsl.outgoing?
          namespace_type = dsl.namespace_type
        else
          clazz = dsl.clazz || node.class
          namespace_type = clazz.decl_relationships[dsl.type].namespace_type
        end
        
        # add index on the trigger class and connect it to the updater_clazz
        # (a trigger may cause an update of the index using the Indexer specified on the updater class)
        trigger_clazz.indexer.add_index_in_relationship_on_property(updater_clazz, rel_name, rel_type, prop, namespace_type.to_sym)
      end


      # Specifies a relationship between two node classes.
      #
      # ==== Example
      #   class Order
      #      include Neo4j::NodeMixin      
      #      has_one(:customer).to(Customer)
      #   end
      #
      # :api: public
      def has_one(rel_type, params = {})
        clazz = self
        module_eval(%Q{def #{rel_type}=(value)
                        dsl = #{clazz}.decl_relationships[:'#{rel_type.to_s}']
                        r = Relationships::HasN.new(self, dsl)
                        r << value
                        r
                    end},  __FILE__, __LINE__)

        module_eval(%Q{def #{rel_type}
                        dsl = #{clazz}.decl_relationships[:'#{rel_type.to_s}']
                        r = Relationships::HasN.new(self, dsl)
                        [*r][0]
                    end},  __FILE__, __LINE__)
        decl_relationships[rel_type.to_sym] = Relationships::DeclRelationshipDsl.new(rel_type, params)
      end


      # Specifies a relationship between two node classes.
      #
      # ==== Example
      #   class Order
      #      include Neo4j::NodeMixin
      #      has_n(:order_lines).to(Product).relationship(OrderLine)
      #   end
      #
      # :api: public
      def has_n(rel_type, params = {})
        clazz = self
        module_eval(%Q{
                    def #{rel_type}(&block)
                        dsl = #{clazz}.decl_relationships[:'#{rel_type.to_s}']
                        Relationships::HasN.new(self, dsl, &block)
                    end},  __FILE__, __LINE__)
        decl_relationships[rel_type.to_sym] = Relationships::DeclRelationshipDsl.new(rel_type, params)
      end


      # Specifies a relationship to a linked list of nodes.
      # Each list item class may (but not necessarily  use the belongs_to_list
      # in order to specify which ruby class should be loaded when a list item is loaded.
      #
      # Example
      #
      #  class Company
      #    include Neo4j::NodeMixin
      #    has_list :employees
      #  end
      #
      #  company = Company.new
      #  company.employees << employee1 << employee2
      #
      #  # prints first employee2 and then employee1
      #  company.employees.each {|employee| puts employee.name}
      #
      # ===== Size Counter
      # If the optional parameter :size is given then the list will contain a size counter.
      #
      # Example
      #
      #  class Company
      #    include Neo4j::NodeMixin
      #    has_list :employees, :counter => true
      #  end
      #
      #  company = Company.new
      #  company.employees << employee1 << employee2
      #  company.employees.size # => 2
      #
      # ==== Deleted List Items
      #
      # The list will be updated if an item is deleted in a list.
      # Example:
      #
      #  company = Company.new
      #  company.employees << employee1 << employee2 << employee3
      #  company.employees.size # => 3
      #
      #  employee2.del
      #
      #  [*company.employees] # => [employee1, employee3]
      #  company.employees.size # => 2
      #
      # ===== List Items Memberships
      #
      #  For deciding which lists a node belongs to see the Neo4j::NodeMixin#list method
      #
      # :api: public
      def has_list(rel_type, params = {})
        clazz = self
        #(self.kind_of?(Module))? self : self.class
        module_eval(%Q{
                    def #{rel_type}(&block)
                        dsl = #{clazz}.decl_relationships[:'#{rel_type.to_s}']
                        Relationships::HasList.new(self, dsl, &block)
                    end},  __FILE__, __LINE__)
        Neo4j.event_handler.add Relationships::HasList
        decl_relationships[rel_type.to_sym] = Relationships::DeclRelationshipDsl.new(rel_type, params)
      end


      # Can be used together with the has_list to specify the ruby class of a list item.
      #
      # :api: public
      def belongs_to_list(rel_type, params = {})
        decl_relationships[rel_type] = Relationships::DeclRelationshipDsl.new(rel_type, params)
      end


      # Finds all nodes of this type (and ancestors of this type) having
      # the specified property values.
      # See the lucene module for more information how to do a query.
      #
      # ==== Example
      #   MyNode.find(:name => 'foo', :company => 'bar')
      #
      # Or using a DSL query (experimental)
      #   MyNode.find{(name == 'foo') & (company == 'bar')}
      #
      # ==== Returns
      # Neo4j::SearchResult
      #
      # :api: public
      def find(query=nil, &block)
        self.indexer.find(query, block)
      end


      # Creates a new value object class (a Struct) representing this class.
      #
      # The struct will have the Ruby on Rails method: model_name and
      # new_record? so that it can be used for restful routing.
      #
      # @api private
      def create_value_class # :nodoc:
        # the name of the class we want to create
        name = "#{self.to_s}ValueObject".gsub("::", '_')

        # remove previous class if exists
        Neo4j.instance_eval do
          remove_const name
        end if Neo4j.const_defined?(name)

        # get the properties we want in the new class
        props = self.properties_info.keys.map{|k| ":#{k}"}.join(',')
        Neo4j.module_eval %Q[class #{name} < Struct.new(#{props}); end]

        # get reference to the new class
        clazz = Neo4j.const_get(name)

        # make it more Ruby on Rails friendly - try adding model_name method
        if self.respond_to?(:model_name)
          model = self.model_name.clone
          (
          class << clazz;
            self;
          end).instance_eval do
            define_method(:model_name) {model}
          end
        end

        # by calling the _update method we change the state of the struct
        # so that new_record returns false - Ruby on Rails
        clazz.instance_eval do
          define_method(:_update) do |hash|
            @_updated = true
            hash.each_pair {|key, value| self[key.to_sym] = value if members.include?(key.to_s) }
          end
          define_method(:new_record?) { ! defined?(@_updated) }
        end

        clazz
      end

    end
  end
end
