$LOAD_PATH << File.expand_path(File.dirname(__FILE__) + "/../../lib")
$LOAD_PATH << File.expand_path(File.dirname(__FILE__) + "/..")

require 'neo4j'
require 'spec_helper'


describe "Neo4j::NodeMixin#has_one " do
  before(:all) do
    start
    undefine_class :Person, :Address

    class Address
    end

    class Person
      include Neo4j::NodeMixin
      has_one(:address).to(Address)
    end

    class Address
      include Neo4j::NodeMixin
      property :city, :road
      has_n(:people).from(Person, :address)
    end

  end

   before(:each) do
     Neo4j::Transaction.new
   end

   after(:each) do
     Neo4j::Transaction.finish
   end

  it "should create a relationship with assignment like node1.rel = node2" do
    # given
    person = Person.new

    # when
    person.address = Address.new {|a| a.city = 'malmoe'; a.road = 'my road'}

    # then
    person.address.should be_kind_of(Address)
    [*person.address.people].size.should == 1
    [*person.address.people].should include(person)
  end

  it "should create a relationship with the new method, like node1.rel.new(node2)" do
    # given
    person  = Person.new
    address = Address.new {|a| a.city = 'malmoe'; a.road = 'my road'}

    # when
    address.people.new(person)

    # then
    person.address.should be_kind_of(Address)
    [*person.address.people].size.should == 1
    [*person.address.people].should include(person)
  end

  it "should create a relationship with correct relationship type" do
    # given
    person  = Person.new
    address = Address.new {|a| a.city = 'malmoe'; a.road = 'my road'}

    # when
    dynamic_relationship = address.people.new(person)

    # then
    dynamic_relationship.relationship_type.should == :"Address#address"
  end
  
  it "should should return the object using the has_one accessor" do
    a = Address.new
    p = Person.new

    # when
    a.people << p

    # then
    p.address.should == a
  end

end