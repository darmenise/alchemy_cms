require 'spec_helper'

shared_examples_for "an essence" do

  let(:element) { Alchemy::Element.new }
  let(:content) { Alchemy::Content.new(name: 'foo') }
  let(:content_description) { {'name' => 'foo'} }

  it "touches the content after update" do
    essence.save
    content.update(essence: essence, essence_type: essence.class.name)
    d = content.updated_at
    content.essence.update(essence.ingredient_column.to_sym => ingredient_value)
    content.reload
    content.updated_at.should_not eq(d)
  end

  it "should have correct partial path" do
    underscored_essence = essence.class.name.demodulize.underscore
    expect(essence.to_partial_path).to eq("alchemy/essences/#{underscored_essence}_view")
  end

  describe '#description' do
    subject { essence.description }

    context 'without element' do
      it { should eq({}) }
    end

    context 'with element' do
      before { essence.stub(element: element) }

      context 'but without content descriptions' do
        it { should eq({}) }
      end

      context 'and content descriptions' do
        before do
          essence.stub(content: content)
        end

        context 'containing the content name' do
          before { element.stub(content_descriptions: [content_description]) }

          it "returns the content description" do
            should eq(content_description)
          end
        end

        context 'not containing the content name' do
          before { element.stub(content_descriptions: []) }

          it { should eq({}) }
        end
      end
    end
  end

  describe '#ingredient=' do
    it 'should set the value to ingredient column' do
      essence.ingredient = ingredient_value
      expect(essence.ingredient).to eq ingredient_value
    end
  end

  describe 'validations' do
    context 'without essence description in elements.yml' do
      it 'should return an empty array' do
        essence.stub(:description).and_return nil
        expect(essence.validations).to eq([])
      end
    end

    context 'without validations defined in essence description in elements.yml' do
      it 'should return an empty array' do
        essence.stub(:description).and_return({name: 'test', type: 'EssenceText'})
        expect(essence.validations).to eq([])
      end
    end

    describe 'presence' do
      before do
        essence.stub(:description).and_return({'validate' => ['presence']})
      end

      context 'when the ingredient column is empty' do
        before { essence.update(essence.ingredient_column.to_sym => nil) }

        it 'should not be valid' do
          expect(essence).to_not be_valid
        end
      end

      context 'when the ingredient column is not nil' do
        before { essence.update(essence.ingredient_column.to_sym => ingredient_value) }

        it 'should be valid' do
          expect(essence).to be_valid
        end
      end
    end

    describe 'uniqueness' do
      before do
        essence.stub(element: build_stubbed(:element))
        essence.stub(:description).and_return({'validate' => ['uniqueness']})
        essence.update(essence.ingredient_column.to_sym => ingredient_value)
      end

      context 'when a duplicate exists' do
        before { essence.stub(:duplicates).and_return([essence.dup]) }

        it 'should not be valid' do
          expect(essence).to_not be_valid
        end

        context 'when validated essence is not public' do
          before { essence.stub(public?: false) }

          it 'should be valid' do
            expect(essence).to be_valid
          end
        end
      end

      context 'when no duplicate exists' do
        before { essence.stub(:duplicates).and_return([]) }

        it 'should be valid' do
          expect(essence).to be_valid
        end
      end
    end

    describe '#acts_as_essence?' do
      it 'should return true' do
        expect(essence.acts_as_essence?).to be_true
      end
    end
  end
end

shared_examples_for "an essence editor partial" do
  let(:element) { Alchemy::Element.new }
  let(:content) { build_stubbed(:content, essence: essence, name: 'I am content', element: element) }

  before do
    content.element = element
    content.stub(description: {name: content.name})
    content.stub(settings: {deletable: true})
    content.stub(hint: "I am a hint")
    render_essence_editor(content)
  end

  it "has an id attribute" do
    expect(rendered).to have_selector("[id=\"#{content.dom_id}\"]")
  end

  it "has a data-content-id attribute" do
    expect(rendered).to have_selector("[data-content-id=\"#{content.id}\"]")
  end

  it "has an essence_editor class" do
    expect(rendered).to have_selector(".content_editor")
  end

  it "has a class for essence_type" do
    expect(rendered).to have_selector(".#{content.essence_type.to_s.demodulize.underscore}")
  end

  it "has a label with name in it" do
    expect(rendered).to have_selector(".content_editor label")
    expect(rendered).to have_content(content.name_for_label)
  end

  context 'with settings[:deletable] true' do
    it "has a link for removing the content" do
      expect(rendered).to have_selector("label a[data-alchemy-confirm-delete]")
    end
  end

  context 'with hint present' do
    it "has a hint icon" do
      expect(rendered).to have_selector("label a.hint")
      expect(rendered).to have_content("I am a hint")
    end
  end
end
